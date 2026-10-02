-- npx wrangler@4 d1 execute church-install-stats --remote --file stats-worker/report.sql
-- Funnel: wizards opened, installs started, installs finished (each counted once).
SELECT
  (SELECT COUNT(DISTINCT session) FROM events WHERE event = 'opened') AS opened,
  (SELECT COUNT(DISTINCT run_id) FROM events WHERE event = 'started') AS started,
  (SELECT COUNT(DISTINCT run_id) FROM events WHERE event = 'completed') AS completed;
-- Where unfinished installs last stopped.
SELECT step, code, COUNT(*) AS installs FROM (
  SELECT run_id, step, code FROM events e WHERE event = 'stopped'
    AND id = (SELECT MAX(id) FROM events WHERE run_id = e.run_id AND event = 'stopped')
    AND run_id NOT IN (SELECT run_id FROM events WHERE event = 'completed')
) GROUP BY step, code ORDER BY installs DESC;
-- Every stop, finished or not: which steps trip people up most.
SELECT step, code, COUNT(*) AS stops, COUNT(DISTINCT run_id) AS installs
FROM events WHERE event = 'stopped' GROUP BY step, code ORDER BY stops DESC;
