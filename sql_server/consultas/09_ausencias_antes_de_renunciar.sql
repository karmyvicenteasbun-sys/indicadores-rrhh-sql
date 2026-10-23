-- =====================================================================
-- 09. ¿Las ausencias avisan una renuncia? (versión SQL Server)
-- Pregunta: ¿cuánto faltan las personas en los 3 meses antes de renunciar,
--           comparado con el resto del tiempo?
-- Técnicas: LEFT JOIN para separar a quienes renunciaron, CASE para armar
--           grupos y distancia en meses con DATEDIFF(MONTH, ...).
-- Grupos: los 3 últimos meses antes de renunciar (incluye el mes de la
-- renuncia), los meses anteriores de esas mismas personas y quienes no
-- renunciaron.
-- =====================================================================
WITH renuncias AS (
    SELECT id_colaborador, fecha_egreso
    FROM dbo.colaboradores
    WHERE tipo_egreso = N'Renuncia voluntaria'
),
meses AS (
    SELECT pl.id_colaborador,
           pl.periodo,
           pl.dias_ausencia,
           pl.dias_trabajados,
           CASE
               WHEN r.id_colaborador IS NULL THEN N'3. Quienes no renunciaron'
               WHEN DATEDIFF(MONTH, pl.fecha_periodo, r.fecha_egreso) <= 2
                   THEN N'1. Últimos 3 meses antes de renunciar'
               ELSE N'2. Meses anteriores de quienes renunciaron'
           END AS grupo
    FROM dbo.planilla_mensual AS pl
    LEFT JOIN renuncias AS r ON r.id_colaborador = pl.id_colaborador
),
faltas AS (
    SELECT id_colaborador, CONVERT(CHAR(7), fecha_inicio, 126) AS periodo, SUM(dias) AS dias_falta
    FROM dbo.ausencias
    WHERE tipo = N'Falta injustificada'
    GROUP BY id_colaborador, CONVERT(CHAR(7), fecha_inicio, 126)
)
SELECT m.grupo,
       COUNT(*)                                                               AS meses_persona,
       SUM(m.dias_ausencia)                                                   AS dias_ausencia,
       ROUND(1.0 * SUM(m.dias_ausencia) / SUM(m.dias_trabajados), 4)          AS ausentismo,
       ROUND(1.0 * SUM(COALESCE(f.dias_falta, 0)) / SUM(m.dias_ausencia), 3)  AS pct_faltas_injustificadas
FROM meses AS m
LEFT JOIN faltas AS f ON f.id_colaborador = m.id_colaborador AND f.periodo = m.periodo
GROUP BY m.grupo
ORDER BY m.grupo;
