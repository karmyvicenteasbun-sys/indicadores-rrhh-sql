-- =====================================================================
-- Objetos reutilizables para SQL Server
--   dbo.v_ausentismo_mensual     vista lista para conectar Power BI
--   dbo.usp_costo_ausentismo     costo del ausentismo para cualquier período
--   dbo.usp_alerta_horas_extra   rachas de horas extra con umbral y largo variables
--   dbo.usp_validar_integridad   controles de calidad de los datos
-- Correr después de 00_esquema.sql (CREATE OR ALTER: se puede repetir).
-- =====================================================================
SET NOCOUNT ON;
GO

-- Ausentismo por mes, área y turno: una fila por combinación, sin cálculos
-- de porcentaje para que Power BI pueda sumar y después dividir (DIVIDE).
CREATE OR ALTER VIEW dbo.v_ausentismo_mensual AS
SELECT p.fecha_periodo,
       p.periodo,
       v.area,
       v.turno,
       COUNT(*)               AS dotacion,
       SUM(p.dias_trabajados) AS dias_en_planilla,
       SUM(p.dias_ausencia)   AS dias_ausencia,
       SUM(p.horas_extra)     AS horas_extra,
       SUM(p.costo_total_bs)  AS costo_total_bs
FROM dbo.planilla_mensual AS p
JOIN dbo.v_colaboradores  AS v ON v.id_colaborador = p.id_colaborador
GROUP BY p.fecha_periodo, p.periodo, v.area, v.turno;
GO

-- Costo del ausentismo por área entre dos fechas (incluidas).
-- Ejemplo: EXEC dbo.usp_costo_ausentismo @desde = '20251001', @hasta = '20260930';
CREATE OR ALTER PROCEDURE dbo.usp_costo_ausentismo
    @desde DATE,
    @hasta DATE
AS
BEGIN
    SET NOCOUNT ON;

    IF @desde IS NULL OR @hasta IS NULL OR @hasta < @desde
        THROW 50010, N'Revisar las fechas: @desde y @hasta son obligatorias y @hasta no puede ser anterior a @desde.', 1;

    DECLARE @carga FLOAT, @recargo FLOAT, @horas_mes FLOAT, @horas_jornada FLOAT,
            @cobertura_lineas FLOAT, @cobertura_otras FLOAT;

    SELECT @carga = MAX(CASE WHEN clave = 'aportes_patronales' THEN valor END)
                  + MAX(CASE WHEN clave = 'provision_aguinaldo' THEN valor END)
                  + MAX(CASE WHEN clave = 'provision_indemnizacion' THEN valor END),
           @recargo          = MAX(CASE WHEN clave = 'recargo_horas_extra' THEN valor END),
           @horas_mes        = MAX(CASE WHEN clave = 'horas_mes' THEN valor END),
           @horas_jornada    = MAX(CASE WHEN clave = 'horas_jornada' THEN valor END),
           @cobertura_lineas = MAX(CASE WHEN clave = 'cobertura_operativos_lineas' THEN valor END),
           @cobertura_otras  = MAX(CASE WHEN clave = 'cobertura_operativos_otras' THEN valor END)
    FROM dbo.parametros;

    IF @carga IS NULL OR @recargo IS NULL OR @horas_mes IS NULL OR @horas_jornada IS NULL
       OR @cobertura_lineas IS NULL OR @cobertura_otras IS NULL
        THROW 50011, N'Faltan parámetros en dbo.parametros.', 1;

    WITH costos AS (
        SELECT v.area,
               a.dias,
               CASE WHEN a.tipo <> N'Falta injustificada'
                    THEN a.dias * pl.haber_basico_bs / 30.0 * (1 + @carga) ELSE 0 END AS costo_dias_pagados,
               a.dias
                 * CASE WHEN v.nivel <> N'Operativo' THEN 0
                        WHEN v.area IN (N'Producción', N'Logística y Distribución') THEN @cobertura_lineas
                        ELSE @cobertura_otras END
                 * @horas_jornada * pl.haber_basico_bs / @horas_mes * @recargo * (1 + @carga) AS costo_cobertura
        FROM dbo.ausencias        AS a
        JOIN dbo.v_colaboradores  AS v  ON v.id_colaborador = a.id_colaborador
        JOIN dbo.planilla_mensual AS pl ON pl.id_colaborador = a.id_colaborador
                                       AND pl.periodo = CONVERT(CHAR(7), a.fecha_inicio, 126)
        WHERE a.fecha_inicio BETWEEN @desde AND @hasta
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
                 / NULLIF(SUM(costo_dias_pagados_bs + costo_cobertura_bs) OVER (), 0), 3) AS pct_del_costo
    FROM por_area
    ORDER BY costo_total_bs DESC;
END;
GO

-- Rachas de meses seguidos con horas extra sobre un umbral.
-- Sin @umbral usa el valor de dbo.parametros (40 horas).
-- Ejemplos:
--   EXEC dbo.usp_alerta_horas_extra @desde = '20251001';
--   EXEC dbo.usp_alerta_horas_extra @desde = '20251001', @umbral = 50, @meses_minimos = 2;
CREATE OR ALTER PROCEDURE dbo.usp_alerta_horas_extra
    @desde          DATE,
    @umbral         FLOAT = NULL,
    @meses_minimos  INT   = 3
AS
BEGIN
    SET NOCOUNT ON;

    IF @umbral IS NULL
        SELECT @umbral = valor FROM dbo.parametros WHERE clave = 'umbral_horas_extra_mes';

    DECLARE @ultimo_periodo CHAR(7) = (SELECT MAX(periodo) FROM dbo.planilla_mensual);

    WITH islas AS (
        SELECT id_colaborador, periodo, horas_extra,
               YEAR(fecha_periodo) * 12 + MONTH(fecha_periodo)
               - ROW_NUMBER() OVER (PARTITION BY id_colaborador ORDER BY fecha_periodo) AS isla
        FROM dbo.planilla_mensual
        WHERE horas_extra > @umbral
          AND fecha_periodo >= @desde
    ),
    rachas AS (
        SELECT id_colaborador,
               MIN(periodo)                              AS desde,
               MAX(periodo)                              AS hasta,
               COUNT(*)                                  AS meses_seguidos,
               ROUND(AVG(CAST(horas_extra AS FLOAT)), 1) AS horas_extra_promedio
        FROM islas
        GROUP BY id_colaborador, isla
        HAVING COUNT(*) >= @meses_minimos
    )
    SELECT r.id_colaborador, v.area, v.cargo, v.turno, r.desde, r.hasta, r.meses_seguidos, r.horas_extra_promedio,
           CASE WHEN r.hasta = @ultimo_periodo THEN N'Sigue' ELSE N'Terminó' END AS situacion
    FROM rachas AS r
    JOIN dbo.v_colaboradores AS v ON v.id_colaborador = r.id_colaborador
    ORDER BY r.meses_seguidos DESC, r.horas_extra_promedio DESC;
END;
GO

-- Controles de calidad: cada fila es un control con la cantidad de problemas.
-- Todo en 0 = datos consistentes.
CREATE OR ALTER PROCEDURE dbo.usp_validar_integridad
AS
BEGIN
    SET NOCOUNT ON;

    SELECT control, problemas
    FROM (VALUES
        (1, N'Meses con días de ausencia que no cuadran con el detalle',
            (SELECT COUNT(*)
             FROM dbo.planilla_mensual AS p
             LEFT JOIN (SELECT id_colaborador, CONVERT(CHAR(7), fecha_inicio, 126) AS periodo, SUM(dias) AS dias
                        FROM dbo.ausencias
                        GROUP BY id_colaborador, CONVERT(CHAR(7), fecha_inicio, 126)) AS a
                    ON a.id_colaborador = p.id_colaborador AND a.periodo = p.periodo
             WHERE p.dias_ausencia <> COALESCE(a.dias, 0))),
        (2, N'Ausencias fuera de la relación laboral',
            (SELECT COUNT(*)
             FROM dbo.ausencias AS a
             JOIN dbo.colaboradores AS c ON c.id_colaborador = a.id_colaborador
             WHERE a.fecha_inicio < c.fecha_ingreso
                OR (c.fecha_egreso IS NOT NULL AND a.fecha_fin > c.fecha_egreso))),
        (3, N'Planillas de meses en los que la persona no estaba',
            (SELECT COUNT(*)
             FROM dbo.planilla_mensual AS p
             JOIN dbo.colaboradores AS c ON c.id_colaborador = p.id_colaborador
             WHERE EOMONTH(p.fecha_periodo) < c.fecha_ingreso
                OR (c.fecha_egreso IS NOT NULL AND p.fecha_periodo > c.fecha_egreso))),
        (4, N'Ausencias que cruzan de un mes a otro',
            (SELECT COUNT(*)
             FROM dbo.ausencias
             WHERE CONVERT(CHAR(7), fecha_inicio, 126) <> CONVERT(CHAR(7), fecha_fin, 126))),
        (5, N'Ausencias de una misma persona que se superponen',
            (SELECT COUNT(*)
             FROM dbo.ausencias AS a
             JOIN dbo.ausencias AS b ON b.id_colaborador = a.id_colaborador
                                    AND b.id_ausencia > a.id_ausencia
                                    AND b.fecha_inicio <= a.fecha_fin
                                    AND b.fecha_fin >= a.fecha_inicio))
    ) AS t (orden, control, problemas)
    ORDER BY orden;
END;
GO
