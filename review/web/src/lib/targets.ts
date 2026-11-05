// Where the reviewable parts of an entry sit: the TypeScript twin of review/api's `find_part` and the
// item walk in items.rs. Keep the three in step.
import type { Dataset } from './api.ts';
import { isKanji, segments } from './ruby.ts';

// Published entries are loosely typed JSON here; the Worker has already checked their shape.
type Json = { [key: string]: any };

export type Kind = 'entry' | 'example' | 'collocation' | 'usage' | 'pitfall' | 'thing';
export type Part = { kind: Kind; id: string; value: Json };

const list = (value: unknown): Json[] => (Array.isArray(value) ? value : []);

/** The entry's id as the API names it. */
export function entryId(dataset: Dataset, entry: Json): string {
	if (dataset === 'verbs') return entry.id ?? entry.dict;
	if (dataset === 'words') return `${entry.class}:${entry.dict}`;
	return entry.id;
}

/** The entry first, then every part with a stable id, in document order. */
export function partsOf(dataset: Dataset, entry: Json): Part[] {
	const out: Part[] = [{ kind: 'entry', id: entryId(dataset, entry), value: entry }];
	const add = (kind: Kind, items: Json[]) => items.forEach((value) => out.push({ kind, id: value.id, value }));
	const sections = (kind: Kind, key: string) =>
		list(entry[key]).forEach((section) => {
			add(kind, [section]);
			add('example', list(section.examples));
		});
	if (dataset === 'verbs') {
		add('example', list(entry.examples));
		add('collocation', list(entry.collocations));
	} else if (dataset === 'counters') {
		add('thing', list(entry.things));
		add('example', list(entry.examples));
		sections('pitfall', 'pitfalls');
	} else if (dataset === 'grammar') {
		sections('usage', 'usages');
		sections('pitfall', 'pitfalls');
		// A contrast's own id names another grammar point; only its examples are parts.
		list(entry.contrasts).forEach((contrast) => add('example', list(contrast.examples)));
	}
	return out;
}

const KEYS: Record<Exclude<Kind, 'entry'>, string> = {
	example: 'examples',
	collocation: 'collocations',
	usage: 'usages',
	pitfall: 'pitfalls',
	thing: 'things'
};

/** The part of `kind` with the stable `id` inside `entry` (the entry itself for `entry`). */
export function partOf(entry: Json, kind: string, id: string): Json | undefined {
	if (kind === 'entry') return entry;
	const key = KEYS[kind as Exclude<Kind, 'entry'>];
	if (!key) return undefined;
	const lists = [list(entry[key])];
	if (kind === 'example') {
		for (const section of ['usages', 'pitfalls', 'contrasts']) {
			for (const owner of list(entry[section])) lists.push(list(owner.examples));
		}
	}
	return lists.flat().find((part) => part.id === id);
}

/** The distinct runs of kanji in `text` that `readings` gives no furigana for. */
export function unknownKanjiRuns(text: string, readings: Record<string, string>): string[] {
	const runs: string[] = [];
	for (const segment of segments(text, readings)) {
		if (segment.reading !== undefined) continue;
		let run = '';
		for (const ch of [...Array.from(segment.text), '']) {
			if (ch && isKanji(ch)) run += ch;
			else if (run) {
				if (!runs.includes(run)) runs.push(run);
				run = '';
			}
		}
	}
	return runs;
}
