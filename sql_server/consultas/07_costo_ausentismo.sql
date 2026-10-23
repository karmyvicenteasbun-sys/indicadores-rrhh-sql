-- =====================================================================
-- 07. Costo del ausentismo por área, oct-2025 a sep-2026 (versión SQL Server)
-- Pregunta: ¿cuánto cuesta el ausentismo y qué parte es cubrir el puesto?
-- Es la misma lógica que dbo.usp_costo_ausentismo (02_procedimientos.sql),
-- con el período fijo. Ver supuestos en consultas/07_costo_ausentismo.sql.
-- Técnicas: parámetros leídos de una tabla (pivot con MAX(CASE ...)),
--           CROSS JOIN, JOIN con la planilla del mes de cada ausencia y
--           porcentajes con SUM() OVER ().
-- =====================================================================
WITH p AS (
    SELECT MAX(CASE WHEN clave = 'aportes_patronales' THEN valor END)
         + MAX(CASE WHEN clave = 'provision_aguinaldo' THEN valor END)
         + MAX(CASE WHEN clave = 'provision_indemnizacion' THEN valor END) AS carga,
           MAX(CASE WHEN clave = 'recargo_horas_extra' THEN valor END)          AS recargo,
           MAX(CASE WHEN clave = 'horas_mes' THEN valor END)                    AS horas_mes,
           MAX(CASE WHEN clave = 'horas_jornada' THEN valor END)                AS horas_jornada,
           MAX(CASE WHEN clave = 'cobertura_operativos_lineas' THEN valor END)  AS cobertura_lineas,
           MAX(CASE WHEN clave = 'cobertura_operativos_otras' THEN valor END)   AS cobertura_otras
    FROM dbo.parametros
),
dias AS (
    SELECT v.area, v.nivel, a.tipo, a.dias, pl.haber_basico_bs
    FROM dbo.ausencias        AS a
    JOIN dbo.v_colaboradores  AS v  ON v.id_colaborador = a.id_colaborador
    JOIN dbo.planilla_mensual AS pl ON pl.id_colaborador = a.id_colaborador
                                   AND pl.periodo = CONVERT(CHAR(7), a.fecha_inicio, 126)
    WHERE a.fecha_inicio BETWEEN '20251001' AND '20260930'
),
costos AS (
    SELECT d.area,
           d.dias,
           CASE WHEN d.tipo <> N'Falta injustificada'
                THEN d.dias * d.haber_basico_bs / 30.0 * (1 + p.carga) ELSE 0 END AS costo_dias_pagados,
           d.dias
             * CASE WHEN d.nivel <> N'Operativo' THEN 0
                    WHEN d.area IN (N'Producción', N'Logística y Distribución') THEN p.cobertura_lineas
                    ELSE p.cobertura_otras END
             * p.horas_jornada * d.haber_basico_bs / p.horas_mes * p.recargo * (1 + p.carga) AS costo_cobertura
    FROM dias AS d
    CROSS JOIN p
),
por_area AS (
    SELECT area,
           SUM(dias)               AS dias_ausencia,
           SUM(costo_dias_pagados) AS costo_dias_pagados_bs,
           SUM(costo_cobertura)    AS costo_cobertura_bs
    FROM costos
    GROUP BY area
)
SELECT area,
       dias_ausencia,
       ROUND(costo_dias_pagados_bs, 0)                       AS costo_dias_pagados_bs,
       ROUND(costo_cobertura_bs, 0)                          AS costo_cobertura_bs,
       ROUND(costo_dias_pagados_bs + costo_cobertura_bs, 0)  AS costo_total_bs,
       ROUND((costo_dias_pagados_bs + costo_cobertura_bs)
             / SUM(costo_dias_pagados_bs + costo_cobertura_bs) OVER (), 3) AS pct_del_costo
FROM por_area
ORDER BY costo_total_bs DESC;
