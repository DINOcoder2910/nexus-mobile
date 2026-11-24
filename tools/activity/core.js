// A task's Activity on the iPhone and iPad, with the laptop's own wording (nexus renderer/src/activity.js, decided 2026-10-29): what
// happened to a task, from its file's facts and the data folder's git history, which the hub on the G14 keeps (GET /v2/activity).
// NexusCore's TaskActivity.swift runs this in JavaScriptCore. Built by tools/activity/build.mjs from a nexus checkout into
// Packages/NexusCore/Sources/NexusCore/Resources/activitycore.js. Strings in and out (JSON for objects).
import { taskActivity } from 'nexus/activity.js';

globalThis.NexusActivityCore = {
  // a: {id, path, task: {added, done, doneOn}, versions, trail, current, names: {path: name}, today, now} -> {ok, rows: [{at, date, text, who}]}
  activity(json) {
    try {
      const a = JSON.parse(json);
      const names = a.names || {};
      const rows = taskActivity({ ...a, names: (p) => names[p] || p });
      return JSON.stringify({ ok: true, rows });
    } catch (e) { return JSON.stringify({ ok: false, error: String((e && e.message) || e) }); }
  },
};
