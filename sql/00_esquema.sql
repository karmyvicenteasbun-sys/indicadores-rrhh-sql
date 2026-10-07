-- =====================================================================
-- Esquema de la base de RRHH (SQLite 3.28 o superior)
-- Una embotelladora ficticia: colaboradores, planilla mensual y ausencias.
-- Las fechas se guardan como texto ISO (AAAA-MM-DD), el formato que
-- entienden las funciones de fecha de SQLite.
-- =====================================================================

PRAGMA foreign_keys = ON;

CREATE TABLE areas (
    id_area  INTEGER PRIMARY KEY,
    nombre   TEXT NOT NULL UNIQUE
);

CREATE TABLE niveles (
    id_nivel  INTEGER PRIMARY KEY,
    nombre    TEXT NOT NULL UNIQUE
);

CREATE TABLE cargos (
    id_cargo  INTEGER PRIMARY KEY,
    nombre    TEXT NOT NULL,
    id_area   INTEGER NOT NULL REFERENCES areas (id_area),
    id_nivel  INTEGER NOT NULL REFERENCES niveles (id_nivel),
    UNIQUE (nombre, id_area)
);

CREATE TABLE colaboradores (
    id_colaborador          TEXT PRIMARY KEY,
    id_cargo                INTEGER NOT NULL REFERENCES cargos (id_cargo),
    turno                   TEXT NOT NULL CHECK (turno IN ('Diurno', 'Rotativo')),
    fecha_ingreso           TEXT NOT NULL,
    fecha_egreso            TEXT,                -- NULL mientras la persona está activa
    tipo_egreso             TEXT CHECK (tipo_egreso IN ('Renuncia voluntaria', 'Desvinculación')),
    edad_ingreso            INTEGER,
    distancia_km            REAL,
    compa_ratio             REAL,                -- sueldo / punto medio de su banda
    evaluacion_desempeno    INTEGER CHECK (evaluacion_desempeno BETWEEN 1 AND 5),
    haber_basico_actual_bs  REAL,
    CHECK ((fecha_egreso IS NULL) = (tipo_egreso IS NULL)),
    CHECK (fecha_egreso IS NULL OR fecha_egreso >= fecha_ingreso)
);

CREATE TABLE planilla_mensual (
    periodo                     TEXT NOT NULL,   -- AAAA-MM
    fecha_periodo               TEXT NOT NULL,   -- primer día del mes
    id_colaborador              TEXT NOT NULL REFERENCES colaboradores (id_colaborador),
    dias_trabajados             INTEGER NOT NULL CHECK (dias_trabajados BETWEEN 1 AND 30),  -- días en planilla
    dias_ausencia               INTEGER NOT NULL CHECK (dias_ausencia >= 0),
    horas_extra                 REAL NOT NULL CHECK (horas_extra >= 0),
    haber_basico_bs             REAL NOT NULL,
    basico_pagado_bs            REAL NOT NULL,
    bono_antiguedad_bs          REAL NOT NULL,
    monto_horas_extra_bs        REAL NOT NULL,
    total_ganado_bs             REAL NOT NULL,
    aportes_patronales_bs       REAL NOT NULL,
    provision_aguinaldo_bs      REAL NOT NULL,
    provision_indemnizacion_bs  REAL NOT NULL,
    costo_total_bs              REAL NOT NULL,
    PRIMARY KEY (periodo, id_colaborador)
);

CREATE TABLE ausencias (
    id_ausencia     TEXT PRIMARY KEY,
    id_colaborador  TEXT NOT NULL REFERENCES colaboradores (id_colaborador),
    fecha_inicio    TEXT NOT NULL,
    fecha_fin       TEXT NOT NULL,
    dias            INTEGER NOT NULL CHECK (dias > 0),
    tipo            TEXT NOT NULL CHECK (tipo IN ('Enfermedad con baja médica',
                                                  'Permiso con goce de haber',
                                                  'Falta injustificada')),
    CHECK (fecha_fin >= fecha_inicio)
);

-- Supuestos editables que usan las consultas de costos
CREATE TABLE parametros (
    clave        TEXT PRIMARY KEY,
    valor        REAL NOT NULL,
    descripcion  TEXT NOT NULL
);

CREATE INDEX ix_planilla_colaborador   ON planilla_mensual (id_colaborador);
CREATE INDEX ix_ausencias_colaborador  ON ausencias (id_colaborador, fecha_inicio);
CREATE INDEX ix_ausencias_fecha        ON ausencias (fecha_inicio);
CREATE INDEX ix_colaboradores_cargo    ON colaboradores (id_cargo);

-- Vista de apoyo: cada colaborador con el nombre de su cargo, área y nivel
CREATE VIEW v_colaboradores AS
SELECT c.*,
       cg.nombre AS cargo,
       a.nombre  AS area,
       n.nombre  AS nivel
FROM colaboradores AS c
JOIN cargos  AS cg ON cg.id_cargo = c.id_cargo
JOIN areas   AS a  ON a.id_area   = cg.id_area
JOIN niveles AS n  ON n.id_nivel  = cg.id_nivel;
