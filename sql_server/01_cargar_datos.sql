-- =====================================================================
-- Carga de los CSV de datos/ en SQL Server
-- 1. BULK INSERT de cada CSV a una tabla de paso (todo como texto).
-- 2. Normaliza: áreas, niveles y cargos van a sus propias tablas.
-- 3. Convierte tipos con TRY_CONVERT y carga las tablas finales.
-- 4. Revisa la integridad (lo mismo que crear_base.py en SQLite).
--
-- Antes de correrlo: cambiar @carpeta por la ruta de la carpeta datos/
-- vista DESDE EL SERVIDOR (BULK INSERT lee el archivo en el servidor).
-- Si el servidor no puede leer la carpeta, usar cargar_sql_server.py.
-- =====================================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @carpeta NVARCHAR(400) = N'C:\proyectos\indicadores-rrhh-sql\datos\';

DROP TABLE IF EXISTS #colaboradores, #planilla, #ausencias;

CREATE TABLE #colaboradores (
    id_colaborador NVARCHAR(10), area NVARCHAR(60), cargo NVARCHAR(80), nivel NVARCHAR(60),
    turno NVARCHAR(10), fecha_ingreso NVARCHAR(10), fecha_egreso NVARCHAR(10), tipo_egreso NVARCHAR(30),
    edad_ingreso NVARCHAR(10), distancia_km NVARCHAR(10), compa_ratio NVARCHAR(10),
    evaluacion_desempeno NVARCHAR(10), haber_basico_actual_bs NVARCHAR(20)
);
CREATE TABLE #planilla (
    periodo NVARCHAR(7), fecha_periodo NVARCHAR(10), id_colaborador NVARCHAR(10),
    dias_trabajados NVARCHAR(5), dias_ausencia NVARCHAR(5), horas_extra NVARCHAR(10),
    haber_basico_bs NVARCHAR(20), basico_pagado_bs NVARCHAR(20), bono_antiguedad_bs NVARCHAR(20),
    monto_horas_extra_bs NVARCHAR(20), total_ganado_bs NVARCHAR(20), aportes_patronales_bs NVARCHAR(20),
    provision_aguinaldo_bs NVARCHAR(20), provision_indemnizacion_bs NVARCHAR(20), costo_total_bs NVARCHAR(20)
);
CREATE TABLE #ausencias (
    id_ausencia NVARCHAR(10), id_colaborador NVARCHAR(10), fecha_inicio NVARCHAR(10),
    fecha_fin NVARCHAR(10), dias NVARCHAR(5), tipo NVARCHAR(30)
);

-- BULK INSERT no acepta una variable como ruta: se arma con SQL dinámico
DECLARE @sql NVARCHAR(MAX);
SELECT @sql = STRING_AGG(CAST(N'BULK INSERT ' + t.tabla + N' FROM ''' + REPLACE(@carpeta + t.archivo, N'''', N'''''')
                              + N''' WITH (FORMAT = ''CSV'', FIRSTROW = 2, CODEPAGE = ''65001'', TABLOCK);' AS NVARCHAR(MAX)),
                         CHAR(10))
FROM (VALUES (N'#colaboradores', N'colaboradores.csv'),
             (N'#planilla',      N'planilla_mensual.csv'),
             (N'#ausencias',     N'ausencias.csv')) AS t (tabla, archivo);
EXEC sys.sp_executesql @sql;

BEGIN TRANSACTION;

DELETE FROM dbo.parametros;
DELETE FROM dbo.ausencias;
DELETE FROM dbo.planilla_mensual;
DELETE FROM dbo.colaboradores;
DELETE FROM dbo.cargos;
DELETE FROM dbo.niveles;
DELETE FROM dbo.areas;

-- Mismo orden que en generar_datos.py
INSERT INTO dbo.areas (id_area, nombre)
VALUES (1, N'Producción'), (2, N'Logística y Distribución'), (3, N'Ventas'),
       (4, N'Mantenimiento'), (5, N'Calidad'), (6, N'Administración y Finanzas');

INSERT INTO dbo.niveles (id_nivel, nombre)
VALUES (1, N'Operativo'), (2, N'Técnico y supervisión'), (3, N'Profesional y jefatura');

-- Un id por cargo, ordenado por área, nivel y nombre (igual que en SQLite)
INSERT INTO dbo.cargos (id_cargo, nombre, id_area, id_nivel)
SELECT ROW_NUMBER() OVER (ORDER BY a.id_area, n.id_nivel, x.cargo COLLATE Latin1_General_BIN2),
       x.cargo, a.id_area, n.id_nivel
FROM (SELECT DISTINCT cargo, area, nivel FROM #colaboradores) AS x
JOIN dbo.areas   AS a ON a.nombre = x.area
JOIN dbo.niveles AS n ON n.nombre = x.nivel;

INSERT INTO dbo.colaboradores
SELECT s.id_colaborador, cg.id_cargo, s.turno,
       TRY_CONVERT(DATE, s.fecha_ingreso, 23),
       TRY_CONVERT(DATE, NULLIF(s.fecha_egreso, N''), 23),
       NULLIF(s.tipo_egreso, N''),
       TRY_CONVERT(TINYINT, s.edad_ingreso),
       TRY_CONVERT(DECIMAL(5, 1), s.distancia_km),
       TRY_CONVERT(DECIMAL(4, 2), s.compa_ratio),
       TRY_CONVERT(TINYINT, s.evaluacion_desempeno),
       TRY_CONVERT(DECIMAL(10, 2), s.haber_basico_actual_bs)
FROM #colaboradores AS s
JOIN dbo.areas  AS a  ON a.nombre = s.area
JOIN dbo.cargos AS cg ON cg.nombre = s.cargo AND cg.id_area = a.id_area;

INSERT INTO dbo.planilla_mensual
SELECT periodo, TRY_CONVERT(DATE, fecha_periodo, 23), id_colaborador,
       TRY_CONVERT(TINYINT, dias_trabajados), TRY_CONVERT(TINYINT, dias_ausencia),
       TRY_CONVERT(DECIMAL(6, 2), horas_extra),
       TRY_CONVERT(DECIMAL(10, 2), haber_basico_bs),       TRY_CONVERT(DECIMAL(10, 2), basico_pagado_bs),
       TRY_CONVERT(DECIMAL(10, 2), bono_antiguedad_bs),    TRY_CONVERT(DECIMAL(10, 2), monto_horas_extra_bs),
       TRY_CONVERT(DECIMAL(10, 2), total_ganado_bs),       TRY_CONVERT(DECIMAL(10, 2), aportes_patronales_bs),
       TRY_CONVERT(DECIMAL(10, 2), provision_aguinaldo_bs), TRY_CONVERT(DECIMAL(10, 2), provision_indemnizacion_bs),
       TRY_CONVERT(DECIMAL(10, 2), costo_total_bs)
FROM #planilla;

INSERT INTO dbo.ausencias
SELECT id_ausencia, id_colaborador,
       TRY_CONVERT(DATE, fecha_inicio, 23), TRY_CONVERT(DATE, fecha_fin, 23),
       TRY_CONVERT(TINYINT, dias), tipo
FROM #ausencias;

INSERT INTO dbo.parametros (clave, valor, descripcion)
VALUES ('aportes_patronales',          0.1671,     N'Aportes patronales sobre el total ganado'),
       ('provision_aguinaldo',         1.0 / 12,   N'Provisión mensual de aguinaldo'),
       ('provision_indemnizacion',     1.0 / 12,   N'Provisión mensual de indemnización'),
       ('recargo_horas_extra',         2.0,        N'La hora extra se paga al doble'),
       ('horas_mes',                   240,        N'Horas de un mes de trabajo (30 días x 8 horas)'),
       ('horas_jornada',               8,          N'Horas de una jornada'),
       ('cobertura_operativos_lineas', 0.70,       N'Parte de los días de ausencia de operativos de Producción y Logística que se cubre con horas extra'),
       ('cobertura_operativos_otras',  0.30,       N'Parte de los días de ausencia de operativos de otras áreas que se cubre con horas extra'),
       ('umbral_horas_extra_mes',      40,         N'Horas extra al mes a partir de las que se considera sobrecarga');

-- Controles: que no se haya perdido ninguna fila y que cuadren los días
DECLARE @perdidas INT =
      (SELECT COUNT(*) FROM #colaboradores) - (SELECT COUNT(*) FROM dbo.colaboradores)
    + (SELECT COUNT(*) FROM #planilla)      - (SELECT COUNT(*) FROM dbo.planilla_mensual)
    + (SELECT COUNT(*) FROM #ausencias)     - (SELECT COUNT(*) FROM dbo.ausencias);

DECLARE @descuadres INT = (
    SELECT COUNT(*)
    FROM dbo.planilla_mensual AS p
    LEFT JOIN (SELECT id_colaborador, CONVERT(CHAR(7), fecha_inicio, 126) AS periodo, SUM(dias) AS dias
               FROM dbo.ausencias
               GROUP BY id_colaborador, CONVERT(CHAR(7), fecha_inicio, 126)) AS a
           ON a.id_colaborador = p.id_colaborador AND a.periodo = p.periodo
    WHERE p.dias_ausencia <> COALESCE(a.dias, 0));

IF @perdidas <> 0 OR @descuadres <> 0
BEGIN
    ROLLBACK TRANSACTION;
    THROW 50001, N'Integridad: hay filas perdidas o meses descuadrados. No se cargó nada.', 1;
END;

COMMIT TRANSACTION;

SELECT t.tabla, t.filas
FROM (VALUES (1, N'areas',            (SELECT COUNT(*) FROM dbo.areas)),
             (2, N'niveles',          (SELECT COUNT(*) FROM dbo.niveles)),
             (3, N'cargos',           (SELECT COUNT(*) FROM dbo.cargos)),
             (4, N'colaboradores',    (SELECT COUNT(*) FROM dbo.colaboradores)),
             (5, N'planilla_mensual', (SELECT COUNT(*) FROM dbo.planilla_mensual)),
             (6, N'ausencias',        (SELECT COUNT(*) FROM dbo.ausencias)),
             (7, N'parametros',       (SELECT COUNT(*) FROM dbo.parametros))) AS t (orden, tabla, filas)
ORDER BY t.orden;
