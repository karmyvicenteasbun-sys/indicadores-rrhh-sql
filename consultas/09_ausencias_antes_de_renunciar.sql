-- =====================================================================
-- 09. ¿Las ausencias avisan una renuncia?
-- Pregunta: ¿cuánto faltan las personas en los 3 meses antes de renunciar,
--           comparado con el resto del tiempo?
-- Técnicas: diferencia de meses con aritmética de fechas, CASE para
--           clasificar cada mes y un segundo agregado sobre las ausencias.
-- =====================================================================
WITH renuncias AS (
    SELECT id_colaborador,
           CAST(strftime('%Y', fecha_egreso) AS INTEGER) * 12 + CAST(strftime('%m', fecha_egreso) AS INTEGER) AS mes_egreso
    FROM colaboradores
    WHERE tipo_egreso = 'Renuncia voluntaria'
),
meses AS (
    SELECT pl.id_colaborador,
           pl.periodo,
           pl.dias_ausencia,
           pl.dias_trabajados,
           CASE
               WHEN r.id_colaborador IS NULL THEN '3. Quienes no renunciaron'
               WHEN r.mes_egreso - (CAST(substr(pl.periodo, 1, 4) AS INTEGER) * 12
                                    + CAST(substr(pl.periodo, 6, 2) AS INTEGER)) <= 2
                   THEN '1. Últimos 3 meses antes de renunciar'
               ELSE '2. Meses anteriores de quienes renunciaron'
           END AS grupo
    FROM planilla_mensual AS pl
    LEFT JOIN renuncias AS r ON r.id_colaborador = pl.id_colaborador
),
faltas AS (
    SELECT id_colaborador, strftime('%Y-%m', fecha_inicio) AS periodo, SUM(dias) AS dias_falta
    FROM ausencias
    WHERE tipo = 'Falta injustificada'
    GROUP BY 1, 2
)
SELECT m.grupo,
       COUNT(*)                                                    AS meses_persona,
       SUM(m.dias_ausencia)                                        AS dias_ausencia,
       ROUND(1.0 * SUM(m.dias_ausencia) / SUM(m.dias_trabajados), 4) AS ausentismo,
       ROUND(1.0 * SUM(COALESCE(f.dias_falta, 0)) / SUM(m.dias_ausencia), 3) AS pct_faltas_injustificadas
FROM meses AS m
LEFT JOIN faltas AS f ON f.id_colaborador = m.id_colaborador AND f.periodo = m.periodo
GROUP BY m.grupo
ORDER BY m.grupo;
