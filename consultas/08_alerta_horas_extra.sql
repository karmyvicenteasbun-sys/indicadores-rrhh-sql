-- =====================================================================
-- 08. Alerta de sobrecarga: horas extra altas varios meses seguidos
-- Pregunta: ¿quién hizo más de 40 horas extra al mes durante 3 meses
--           seguidos o más en el último año? (riesgo de fatiga y accidentes)
-- Técnica: "huecos e islas". Si a un número de mes correlativo se le resta
--          ROW_NUMBER(), los meses consecutivos dan el mismo resultado y
--          forman una misma racha.
-- 40 horas al mes son casi 2 horas extra por día hábil.
-- =====================================================================
WITH umbral AS (
    SELECT valor AS horas FROM parametros WHERE clave = 'umbral_horas_extra_mes'
),
meses_altos AS (
    SELECT pl.id_colaborador,
           pl.periodo,
           pl.horas_extra,
           CAST(substr(pl.periodo, 1, 4) AS INTEGER) * 12 + CAST(substr(pl.periodo, 6, 2) AS INTEGER) AS mes_correlativo
    FROM planilla_mensual AS pl
    CROSS JOIN umbral AS u
    WHERE pl.horas_extra > u.horas
      AND pl.periodo >= '2025-10'
),
islas AS (
    SELECT *,
           mes_correlativo - ROW_NUMBER() OVER (PARTITION BY id_colaborador ORDER BY mes_correlativo) AS isla
    FROM meses_altos
),
rachas AS (
    SELECT id_colaborador,
           MIN(periodo)              AS desde,
           MAX(periodo)              AS hasta,
           COUNT(*)                  AS meses_seguidos,
           ROUND(AVG(horas_extra), 1) AS horas_extra_promedio
    FROM islas
    GROUP BY id_colaborador, isla
    HAVING COUNT(*) >= 3
)
SELECT r.id_colaborador, v.area, v.cargo, v.turno, r.desde, r.hasta, r.meses_seguidos, r.horas_extra_promedio,
       CASE WHEN r.hasta = '2026-09' THEN 'Sigue' ELSE 'Terminó' END AS situacion
FROM rachas AS r
JOIN v_colaboradores AS v ON v.id_colaborador = r.id_colaborador
ORDER BY r.meses_seguidos DESC, r.horas_extra_promedio DESC;
