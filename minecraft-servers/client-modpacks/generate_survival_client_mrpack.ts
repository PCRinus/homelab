import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import AdmZip from 'adm-zip';

type LoaderVersion = {
  version?: string;
  gameVersion?: string;
  stable?: boolean;
};

type ProjectInfo = {
  client_side?: string;
};

type VersionFile = {
  primary?: boolean;
  filename?: string;
  hashes?: Record<string, string>;
  url?: string;
  size?: number;
};

type ProjectVersion = {
  files?: VersionFile[];
};

const base = '/home/mircea/homeserver/minecraft-servers';
const outDir = path.join(base, 'client-modpacks');

const envText = await readFile('/tmp/survival-mods.env', 'utf8');
const mcMatch = envText.match(/GENERATED_MC_VERSION='([^']+)'/);
const modsMatch = envText.match(/MODRINTH_PROJECTS_SURVIVAL_ISLAND='([^']+)'/);

if (!mcMatch || !modsMatch) {
  throw new Error('Could not parse /tmp/survival-mods.env');
}

const mcVersion = mcMatch[1];
const entries = modsMatch[1].split(',').map((item) => item.trim()).filter(Boolean);
const slugToVersion = new Map<string, string>();

for (const entry of entries) {
  const [slug, versionId] = entry.split(':', 2);
  if (slug && versionId) {
    slugToVersion.set(slug, versionId);
  }
}

async function fetchJson<T>(url: string): Promise<T> {
  const response = await fetch(url, { signal: AbortSignal.timeout(30_000) });
  if (!response.ok) {
    throw new Error(`HTTP ${response.status} for ${url}`);
  }
  return (await response.json()) as T;
}

let loaderVersion: string | null = null;
const loaderUrls = [
  `https://meta.fabricmc.net/v2/versions/loader/${mcVersion}`,
  'https://meta.fabricmc.net/v2/versions/loader',
];

for (const url of loaderUrls) {
  try {
    const data = await fetchJson<LoaderVersion[]>(url);
    if (!Array.isArray(data) || data.length === 0) {
      continue;
    }

    const candidates = url.endsWith(mcVersion)
      ? data
      : data.filter((item) => typeof item === 'object' && item?.gameVersion === mcVersion);

    const stable = candidates.filter((item) => typeof item === 'object' && item?.stable);
    const pick = stable.length > 0 ? stable : candidates;

    if (pick.length > 0 && pick[0]?.version) {
      loaderVersion = pick[0].version ?? null;
      break;
    }
  } catch {
    continue;
  }
}

if (!loaderVersion) {
  loaderVersion = '0.18.4';
}

const files: Array<{
  path: string;
  hashes: Record<string, string>;
  env: { client: 'required'; server: 'unsupported' };
  downloads: string[];
  fileSize: number;
}> = [];

const excluded: string[] = [];

for (const [slug, versionId] of [...slugToVersion.entries()].sort(([a], [b]) => a.localeCompare(b))) {
  const project = await fetchJson<ProjectInfo>(`https://api.modrinth.com/v2/project/${slug}`);

  if (project.client_side === 'unsupported') {
    excluded.push(slug);
    continue;
  }

  const version = await fetchJson<ProjectVersion>(`https://api.modrinth.com/v2/project/${slug}/version/${versionId}`);
  const versionFiles = version.files ?? [];

  const primary = versionFiles.find((item) => item.primary) ?? versionFiles[0];

  if (!primary || !primary.filename || !primary.url || typeof primary.size !== 'number') {
    throw new Error(`No files for ${slug}:${versionId}`);
  }

  const hashes = primary.hashes ?? {};
  const selectedHashes = Object.fromEntries(
    Object.entries(hashes).filter(([key]) => key === 'sha1' || key === 'sha512'),
  );

  if (Object.keys(selectedHashes).length === 0) {
    throw new Error(`Missing hashes for ${slug}:${versionId}`);
  }

  files.push({
    path: `mods/${primary.filename}`,
    hashes: selectedHashes,
    env: { client: 'required', server: 'unsupported' },
    downloads: [primary.url],
    fileSize: primary.size,
  });
}

const dateStamp = new Date().toISOString().slice(0, 10).replaceAll('-', '');

const index = {
  formatVersion: 1,
  game: 'minecraft',
  versionId: `survival-island-client-${mcVersion}-${dateStamp}`,
  name: `Survival Island Client Pack (${mcVersion})`,
  summary: 'Client-side import pack generated from survival-island resolved Modrinth mods.',
  files,
  dependencies: {
    minecraft: mcVersion,
    'fabric-loader': loaderVersion,
  },
};

await mkdir(outDir, { recursive: true });

const indexPath = path.join(outDir, 'survival-island-client.modrinth.index.json');
await writeFile(indexPath, `${JSON.stringify(index, null, 2)}\n`, 'utf8');

const mrpackPath = path.join(outDir, `survival-island-client-${mcVersion}.mrpack`);
const zip = new AdmZip();
zip.addFile('modrinth.index.json', Buffer.from(JSON.stringify(index), 'utf8'));
zip.writeZip(mrpackPath);

const reportPath = path.join(outDir, `survival-island-client-${mcVersion}.excluded-server-only.txt`);
await writeFile(reportPath, excluded.length > 0 ? `${excluded.join('\n')}\n` : '', 'utf8');

console.log(mrpackPath);
console.log(indexPath);
console.log(reportPath);
console.log(`files=${files.length} excluded=${excluded.length} mc=${mcVersion} fabric-loader=${loaderVersion}`);
