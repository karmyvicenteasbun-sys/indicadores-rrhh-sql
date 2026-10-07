-- =====================================================================
-- 05. Ausencias por día de la semana
-- Pregunta: ¿las faltas injustificadas se concentran en algún día?
-- Técnicas: strftime('%w') para el día de la semana, tabla de días con
--           VALUES y porcentajes con SUM() OVER ().
-- Si las faltas fueran parejas, cada día (lunes a sábado) tendría 1/6 = 16,7%.
-- Último año: oct-2025 a sep-2026.
-- =====================================================================
WITH dias (numero, dia) AS (
    VALUES (1, 'Lunes'), (2, 'Martes'), (3, 'Miércoles'), (4, 'Jueves'), (5, 'Viernes'), (6, 'Sábado')
),
episodios AS (
    SELECT CAST(strftime('%w', fecha_inicio) AS INTEGER) AS numero, tipo
    FROM ausencias
    WHERE fecha_inicio BETWEEN '2025-10-01' AND '2026-09-30'
)
SELECT d.dia,
       SUM(e.tipo = 'Falta injustificada')                    AS faltas_injustificadas,
       ROUND(1.0 * SUM(e.tipo = 'Falta injustificada')
                 / SUM(SUM(e.tipo = 'Falta injustificada')) OVER (), 3) AS pct_de_las_faltas,
       SUM(e.tipo = 'Enfermedad con baja médica')             AS episodios_enfermedad,
       SUM(e.tipo = 'Permiso con goce de haber')              AS permisos
FROM dias AS d
LEFT JOIN episodios AS e ON e.numero = d.numero
GROUP BY d.numero, d.dia
ORDER BY d.numero;
