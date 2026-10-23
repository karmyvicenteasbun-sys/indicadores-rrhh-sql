-- =====================================================================
-- Esquema de la base de RRHH para SQL Server (2017 o superior)
-- Misma base que la versión SQLite: colaboradores, planilla mensual y
-- ausencias de una embotelladora ficticia. Aquí las fechas son DATE, los
-- montos DECIMAL y los textos NVARCHAR.
--
-- Uso (SSMS o sqlcmd), sobre una base vacía:
--     CREATE DATABASE rrhh;   -- una sola vez
--     USE rrhh;
--     -- y después ejecutar este archivo
-- =====================================================================
SET NOCOUNT ON;

-- Borra lo anterior para poder correr el script más de una vez
DROP VIEW  IF EXISTS dbo.v_colaboradores;
DROP TABLE IF EXISTS dbo.parametros, dbo.ausencias, dbo.planilla_mensual,
                     dbo.colaboradores, dbo.cargos, dbo.niveles, dbo.areas;
GO

CREATE TABLE dbo.areas (
    id_area  TINYINT       NOT NULL CONSTRAINT pk_areas PRIMARY KEY,
    nombre   NVARCHAR(60)  NOT NULL CONSTRAINT uq_areas_nombre UNIQUE
);

CREATE TABLE dbo.niveles (
    id_nivel  TINYINT       NOT NULL CONSTRAINT pk_niveles PRIMARY KEY,
    nombre    NVARCHAR(60)  NOT NULL CONSTRAINT uq_niveles_nombre UNIQUE
);

CREATE TABLE dbo.cargos (
    id_cargo  SMALLINT      NOT NULL CONSTRAINT pk_cargos PRIMARY KEY,
    nombre    NVARCHAR(80)  NOT NULL,
    id_area   TINYINT       NOT NULL CONSTRAINT fk_cargos_area  REFERENCES dbo.areas (id_area),
    id_nivel  TINYINT       NOT NULL CONSTRAINT fk_cargos_nivel REFERENCES dbo.niveles (id_nivel),
    CONSTRAINT uq_cargos_nombre_area UNIQUE (nombre, id_area)
);

CREATE TABLE dbo.colaboradores (
    id_colaborador          CHAR(5)        NOT NULL CONSTRAINT pk_colaboradores PRIMARY KEY,
    id_cargo                SMALLINT       NOT NULL CONSTRAINT fk_colaboradores_cargo REFERENCES dbo.cargos (id_cargo),
    turno                   NVARCHAR(10)   NOT NULL CONSTRAINT ck_colaboradores_turno CHECK (turno IN (N'Diurno', N'Rotativo')),
    fecha_ingreso           DATE           NOT NULL,
    fecha_egreso            DATE           NULL,     -- NULL mientras la persona está activa
    tipo_egreso             NVARCHAR(30)   NULL CONSTRAINT ck_colaboradores_tipo_egreso
                                CHECK (tipo_egreso IN (N'Renuncia voluntaria', N'Desvinculación')),
    edad_ingreso            TINYINT        NULL,
    distancia_km            DECIMAL(5, 1)  NULL,
    compa_ratio             DECIMAL(4, 2)  NULL,     -- sueldo / punto medio de su banda
    evaluacion_desempeno    TINYINT        NULL CONSTRAINT ck_colaboradores_evaluacion CHECK (evaluacion_desempeno BETWEEN 1 AND 5),
    haber_basico_actual_bs  DECIMAL(10, 2) NULL,
    CONSTRAINT ck_colaboradores_egreso_completo
        CHECK ((fecha_egreso IS NULL AND tipo_egreso IS NULL) OR (fecha_egreso IS NOT NULL AND tipo_egreso IS NOT NULL)),
    CONSTRAINT ck_colaboradores_fechas CHECK (fecha_egreso IS NULL OR fecha_egreso >= fecha_ingreso)
);

CREATE TABLE dbo.planilla_mensual (
    periodo                     CHAR(7)        NOT NULL,   -- AAAA-MM
    fecha_periodo               DATE           NOT NULL,   -- primer día del mes
    id_colaborador              CHAR(5)        NOT NULL CONSTRAINT fk_planilla_colaborador REFERENCES dbo.colaboradores (id_colaborador),
    dias_trabajados             TINYINT        NOT NULL CONSTRAINT ck_planilla_dias CHECK (dias_trabajados BETWEEN 1 AND 30),
    dias_ausencia               TINYINT        NOT NULL CONSTRAINT ck_planilla_ausencia CHECK (dias_ausencia >= 0),
    horas_extra                 DECIMAL(6, 2)  NOT NULL CONSTRAINT ck_planilla_horas_extra CHECK (horas_extra >= 0),
    haber_basico_bs             DECIMAL(10, 2) NOT NULL,
    basico_pagado_bs            DECIMAL(10, 2) NOT NULL,
    bono_antiguedad_bs          DECIMAL(10, 2) NOT NULL,
    monto_horas_extra_bs        DECIMAL(10, 2) NOT NULL,
    total_ganado_bs             DECIMAL(10, 2) NOT NULL,
    aportes_patronales_bs       DECIMAL(10, 2) NOT NULL,
    provision_aguinaldo_bs      DECIMAL(10, 2) NOT NULL,
    provision_indemnizacion_bs  DECIMAL(10, 2) NOT NULL,
    costo_total_bs              DECIMAL(10, 2) NOT NULL,
    CONSTRAINT pk_planilla PRIMARY KEY (periodo, id_colaborador)
);

CREATE TABLE dbo.ausencias (
    id_ausencia     CHAR(6)       NOT NULL CONSTRAINT pk_ausencias PRIMARY KEY,
    id_colaborador  CHAR(5)       NOT NULL CONSTRAINT fk_ausencias_colaborador REFERENCES dbo.colaboradores (id_colaborador),
    fecha_inicio    DATE          NOT NULL,
    fecha_fin       DATE          NOT NULL,
    dias            TINYINT       NOT NULL CONSTRAINT ck_ausencias_dias CHECK (dias > 0),
    tipo            NVARCHAR(30)  NOT NULL CONSTRAINT ck_ausencias_tipo
                        CHECK (tipo IN (N'Enfermedad con baja médica', N'Permiso con goce de haber', N'Falta injustificada')),
    CONSTRAINT ck_ausencias_fechas CHECK (fecha_fin >= fecha_inicio)
);

-- Supuestos editables que usan las consultas de costos
CREATE TABLE dbo.parametros (
    clave        VARCHAR(40)    NOT NULL CONSTRAINT pk_parametros PRIMARY KEY,
    valor        FLOAT          NOT NULL,
    descripcion  NVARCHAR(200)  NOT NULL
);

CREATE INDEX ix_planilla_colaborador  ON dbo.planilla_mensual (id_colaborador) INCLUDE (dias_ausencia, dias_trabajados, horas_extra);
CREATE INDEX ix_planilla_fecha        ON dbo.planilla_mensual (fecha_periodo);
CREATE INDEX ix_ausencias_colaborador ON dbo.ausencias (id_colaborador, fecha_inicio);
CREATE INDEX ix_ausencias_fecha       ON dbo.ausencias (fecha_inicio) INCLUDE (tipo, dias);
CREATE INDEX ix_colaboradores_cargo   ON dbo.colaboradores (id_cargo);
GO

-- Vista de apoyo: cada colaborador con el nombre de su cargo, área y nivel
CREATE VIEW dbo.v_colaboradores AS
SELECT c.id_colaborador, c.id_cargo, c.turno, c.fecha_ingreso, c.fecha_egreso, c.tipo_egreso,
       c.edad_ingreso, c.distancia_km, c.compa_ratio, c.evaluacion_desempeno, c.haber_basico_actual_bs,
       cg.nombre AS cargo,
       a.nombre  AS area,
       n.nombre  AS nivel
FROM dbo.colaboradores AS c
JOIN dbo.cargos  AS cg ON cg.id_cargo = c.id_cargo
JOIN dbo.areas   AS a  ON a.id_area   = cg.id_area
JOIN dbo.niveles AS n  ON n.id_nivel  = cg.id_nivel;
GO
