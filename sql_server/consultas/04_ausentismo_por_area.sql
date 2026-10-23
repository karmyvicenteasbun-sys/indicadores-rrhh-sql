-- =====================================================================
-- 04. Ausentismo por área y turno, último año contra el anterior (SQL Server)
-- Pregunta: ¿qué áreas y turnos faltan más, y cómo cambió?
-- Técnicas: agregación condicional (CASE dentro de SUM) y UNION ALL.
-- Ausentismo = días de ausencia / días en planilla.
-- Último año: oct-2025 a sep-2026. Año anterior: oct-2024 a sep-2025.
-- =====================================================================
WITH base AS (
    SELECT v.area,
           v.turno,
           CASE WHEN p.fecha_periodo >= '20251001' THEN 'actual' ELSE 'anterior' END AS anio,
           p.dias_ausencia,
           p.dias_trabajados
    FROM dbo.planilla_mensual AS p
    JOIN dbo.v_colaboradores  AS v ON v.id_colaborador = p.id_colaborador
    WHERE p.fecha_periodo >= '20241001'
),
con_total AS (
    SELECT area, turno, anio, dias_ausencia, dias_trabajados FROM base
    UNION ALL
    SELECT N'Toda la empresa', turno, anio, dias_ausencia, dias_trabajados FROM base
)
SELECT area,
       SUM(CASE WHEN anio = 'actual' THEN dias_ausencia END) AS dias_ausencia_ultimo_anio,
       ROUND(1.0 * SUM(CASE WHEN anio = 'actual' THEN dias_ausencia END)
                 / SUM(CASE WHEN anio = 'actual' THEN dias_trabajados END), 4) AS ausentismo_ultimo_anio,
       ROUND(1.0 * SUM(CASE WHEN anio = 'anterior' THEN dias_ausencia END)
                 / SUM(CASE WHEN anio = 'anterior' THEN dias_trabajados END), 4) AS ausentismo_anio_anterior,
       ROUND(1.0 * SUM(CASE WHEN anio = 'actual' AND turno = N'Diurno' THEN dias_ausencia END)
                 / SUM(CASE WHEN anio = 'actual' AND turno = N'Diurno' THEN dias_trabajados END), 4) AS ausentismo_diurno,
       ROUND(1.0 * SUM(CASE WHEN anio = 'actual' AND turno = N'Rotativo' THEN dias_ausencia END)
                 / SUM(CASE WHEN anio = 'actual' AND turno = N'Rotativo' THEN dias_trabajados END), 4) AS ausentismo_rotativo
FROM con_total
GROUP BY area
ORDER BY CASE WHEN area = N'Toda la empresa' THEN 1 ELSE 0 END, ausentismo_ultimo_anio DESC;
