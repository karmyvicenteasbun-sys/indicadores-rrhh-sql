-- =====================================================================
-- 05. Ausencias por día de la semana (versión SQL Server)
-- Pregunta: ¿las faltas injustificadas se concentran en algún día?
-- Técnicas: día de la semana independiente de SET DATEFIRST, tabla de días
--           con VALUES y porcentajes con SUM() OVER ().
-- DATEPART(WEEKDAY) cambia según el idioma del servidor. En cambio,
-- DATEDIFF(DAY, '19000101', fecha) % 7 da 0 el lunes (el 01/01/1900 fue
-- lunes), así que + 1 numera de 1 = lunes a 7 = domingo en cualquier servidor.
-- Si las faltas fueran parejas, cada día (lunes a sábado) tendría 1/6 = 16,7%.
-- Último año: oct-2025 a sep-2026.
-- =====================================================================
WITH dias AS (
    SELECT numero, dia
    FROM (VALUES (1, N'Lunes'), (2, N'Martes'), (3, N'Miércoles'),
                 (4, N'Jueves'), (5, N'Viernes'), (6, N'Sábado')) AS d (numero, dia)
),
episodios AS (
    SELECT DATEDIFF(DAY, '19000101', fecha_inicio) % 7 + 1 AS numero, tipo
    FROM dbo.ausencias
    WHERE fecha_inicio BETWEEN '20251001' AND '20260930'
)
SELECT d.dia,
       SUM(CASE WHEN e.tipo = N'Falta injustificada' THEN 1 ELSE 0 END)          AS faltas_injustificadas,
       ROUND(1.0 * SUM(CASE WHEN e.tipo = N'Falta injustificada' THEN 1 ELSE 0 END)
                 / SUM(SUM(CASE WHEN e.tipo = N'Falta injustificada' THEN 1 ELSE 0 END)) OVER (), 3) AS pct_de_las_faltas,
       SUM(CASE WHEN e.tipo = N'Enfermedad con baja médica' THEN 1 ELSE 0 END)   AS episodios_enfermedad,
       SUM(CASE WHEN e.tipo = N'Permiso con goce de haber' THEN 1 ELSE 0 END)    AS permisos
FROM dias AS d
LEFT JOIN episodios AS e ON e.numero = d.numero
GROUP BY d.numero, d.dia
ORDER BY d.numero;
