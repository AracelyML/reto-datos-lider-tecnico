# ADR 002 · Idempotencia: landing append-only y CDC resuelto en staging

- **Estado:** aceptada
- **Fecha:** 2026-10-27

## Contexto

Las entregas de la réplica se acumulan. Cada una trae registros nuevos y versiones nuevas de registros anteriores, con borrados marcados en `_ab_cdc_deleted_at`. El reto establece que ingerir la misma entrega dos veces, o ejecutar todo dos veces seguidas, no debe duplicar información. Además, la réplica trae filas idénticas repetidas (H4), varias versiones por llave (H5), una sola fecha de extracción para toda la carga (H12) y, a veces, columnas nuevas.

## Decisión

Decidí separar dos problemas que con frecuencia se resuelven juntos:

1. **No volver a cargar un archivo ya cargado** (ingesta). `scripts/ingest.py` hace append a `landing_<sistema>.<tabla>` y registra cada archivo en `landing.ingest_manifest` por hash SHA-256 y tabla. Un archivo con el mismo hash se omite aunque venga en otra carpeta. Cada archivo se carga en una transacción: si falla, rollback y no se registra. Columnas nuevas se agregan a landing (schema drift) y se reportan.
2. **Quedarse con la versión vigente de cada llave** (staging). `cdc_latest` toma la versión de mayor `_ab_cdc_lsn` por llave; si esa versión está borrada, la llave sale. Los duplicados exactos colapsan porque comparten LSN. `cdc_versions` conserva la historia cuando se necesita (SCD2 del segmento).

Landing guarda todo tal como llegó, con `_entrega` y `_archivo_sha256`. Las capas posteriores (staging, silver, gold y marts) se reconstruyen a partir de ahí.

**Contrato mínimo de entrega.** Antes de registrar un archivo se verifica que traiga las columnas CDC, al menos una fila, LSN numérico y `_ab_cdc_updated_at` válido. Si no, queda `rechazado` con su motivo, no se registra y la ingesta termina con error. Un archivo malo nunca entra al manifiesto, así que la entrega corregida se carga normalmente.

## Alternativas consideradas

- **Upsert/merge en landing por llave.** Descartada: pierde la historia de versiones (necesaria para SCD2 y para auditar cambios del origen) y obliga a conocer la llave de cada tabla antes de ingerirla.
- **Controlar por `_airbyte_extracted_at`.** Descartada: toda la carga trae la misma fecha de extracción (H12); no distingue versiones.
- **Controlar por nombre de carpeta o de archivo.** Descartada: la misma entrega reenviada con otro nombre se duplicaría.
- **Deduplicar en el mart.** Descartada: cada mart repetiría la lógica y un mart nuevo podría olvidarla. La regla vive una vez, en staging, como macro.

## Consecuencias

- Ejecutar dos veces es seguro por diseño. El CI lo comprueba en cada PR: dos corridas completas, conteos idénticos y una tercera ingesta en la que todo debe salir `omitido`.
- Landing crece con cada entrega. Con el volumen del reto no importa. En BigQuery, landing se particiona por fecha de ingesta y staging lee solo lo necesario (ver `PROPUESTA.md`).
- Si el origen reenvía un archivo con una corrección mínima, su hash cambia y se carga. Es el comportamiento esperado, porque las versiones nuevas prevalecen por LSN.
- Una columna renombrada en el origen llega como columna nueva y la vieja queda vacía en esas filas. Lo atrapan los tests de staging o de gold, no la ingesta. Se probó con `make chaos ESCENARIO=columna_renombrada`.

## Evidencia

- `make run` ×2: conteos idénticos. La misma entrega copiada en otra carpeta: 5 de 5 archivos omitidos.
- Entrega traslapada con una columna nueva: landing conserva el historial, la columna se agrega y staging no cambia de conteo.
- `make simular` (entrega con viajes nuevos, cambios, borrados, duplicados y columna nueva): marts recalculados de forma independiente coinciden; la segunda carga sale omitida.
- CSV vacío, sin columnas CDC o con LSN no numérico: `rechazado`, exit 1, sin registro en el manifiesto.
