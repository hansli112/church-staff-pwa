import { dateKeyUtc8, serverTime, type Deps } from './common.js';

/** Yesterday's usage from Cloud Monitoring, or null when unavailable. */
export interface Usage {
  firestoreReads: number;
  firestoreWrites: number;
  firestoreDeletes: number;
  storageBytes: number;
  functionCalls: number;
}

export type UsageReader = (start: Date, end: Date) => Promise<Usage | null>;

/**
 * Public list prices (USD) beyond the free tier, asia-east1, 2026-10.
 * Only used for a rough estimate on the stats page.
 */
const PRICE = {
  readsPer100k: 0.036,
  writesPer100k: 0.108,
  deletesPer100k: 0.012,
  storagePerGibMonth: 0.18,
  freeReads: 50_000,
  freeWrites: 20_000,
  freeDeletes: 20_000,
  freeStorageGib: 1,
};

export function estimateCostUsd(u: Usage): number {
  const over = (n: number, free: number) => Math.max(0, n - free);
  const gib = u.storageBytes / 2 ** 30;
  return (
    (over(u.firestoreReads, PRICE.freeReads) / 1e5) * PRICE.readsPer100k +
    (over(u.firestoreWrites, PRICE.freeWrites) / 1e5) * PRICE.writesPer100k +
    (over(u.firestoreDeletes, PRICE.freeDeletes) / 1e5) * PRICE.deletesPer100k +
    (Math.max(0, gib - PRICE.freeStorageGib) * PRICE.storagePerGibMonth) / 30
  );
}

/**
 * Writes stats/{date} for the day before [deps.now()] (UTC+8). Uses set(),
 * so running twice for a day replaces the snapshot instead of adding to it.
 */
export async function writeDailyStats(deps: Deps, readUsage: UsageReader) {
  const { db } = deps;
  const now = deps.now();
  const date = dateKeyUtc8(new Date(now.getTime() - 86400e3));
  // The UTC+8 day [date 00:00, +24h).
  const start = new Date(`${date}T00:00:00+08:00`);
  const end = new Date(start.getTime() + 86400e3);

  const count = async (q: FirebaseFirestore.Query) => (await q.count().get()).data().count;
  const churches = db.collection('churches');
  const [users, active, suspended, deleted, members, rosters] = await Promise.all([
    count(db.collection('users')),
    count(churches.where('status', '==', 'active')),
    count(churches.where('status', '==', 'suspended')),
    count(churches.where('status', '==', 'deleted')),
    count(db.collectionGroup('members')),
    count(db.collectionGroup('rosters')),
  ]);
  let usage: Usage | null = null;
  try {
    usage = await readUsage(start, end);
  } catch {
    usage = null;
  }
  const snapshot = {
    date,
    users,
    churches_active: active,
    churches_suspended: suspended,
    churches_deleted: deleted,
    members,
    rosters,
    ...(usage
      ? {
          firestore_reads: usage.firestoreReads,
          firestore_writes: usage.firestoreWrites,
          firestore_deletes: usage.firestoreDeletes,
          storage_bytes: usage.storageBytes,
          function_calls: usage.functionCalls,
          cost_usd: Math.round(estimateCostUsd(usage) * 100) / 100,
        }
      : {}),
    computedAt: serverTime(),
  };
  await db.doc(`stats/${date}`).set(snapshot);
  return snapshot;
}

/** Reads yesterday's usage from the Cloud Monitoring API. */
export function monitoringUsageReader(projectId: string): UsageReader {
  return async (start, end) => {
    const { MetricServiceClient } = await import('@google-cloud/monitoring');
    const client = new MetricServiceClient();
    const sum = async (metric: string, aligner: 'ALIGN_SUM' | 'ALIGN_MAX' = 'ALIGN_SUM') => {
      const [series] = await client.listTimeSeries({
        name: `projects/${projectId}`,
        filter: `metric.type="${metric}"`,
        interval: {
          startTime: { seconds: Math.floor(start.getTime() / 1000) },
          endTime: { seconds: Math.floor(end.getTime() / 1000) },
        },
        aggregation: {
          alignmentPeriod: { seconds: 86400 },
          perSeriesAligner: aligner,
          crossSeriesReducer: 'REDUCE_SUM',
        },
      });
      let total = 0;
      for (const s of series) {
        for (const p of s.points ?? []) {
          total += Number(p.value?.int64Value ?? p.value?.doubleValue ?? 0);
        }
      }
      return total;
    };
    return {
      firestoreReads: await sum('firestore.googleapis.com/document/read_count'),
      firestoreWrites: await sum('firestore.googleapis.com/document/write_count'),
      firestoreDeletes: await sum('firestore.googleapis.com/document/delete_count'),
      storageBytes: await sum('firestore.googleapis.com/storage/data_and_index_storage_bytes', 'ALIGN_MAX'),
      functionCalls: await sum('cloudfunctions.googleapis.com/function/execution_count'),
    };
  };
}
