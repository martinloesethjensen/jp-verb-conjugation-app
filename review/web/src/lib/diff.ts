// The red pen: what changed between two texts. Japanese compares character by character (code points, so
// a kanji outside the BMP is one character); English compares whole words, which reads far better. A
// longest-common-subsequence diff; fields are at most 2000 characters.

export type Piece = { same?: string; removed?: string; added?: string };

type Kind = keyof Piece;

/** What a diff compares: characters (Japanese) or words with their trailing space (English). */
export type Unit = 'char' | 'word';

function tokens(text: string, unit: Unit): string[] {
	return unit === 'word' ? text.split(/(?<=\s)(?=\S)/).filter(Boolean) : Array.from(text);
}

function push(out: Piece[], kind: Kind, ch: string) {
	const last = out.at(-1);
	if (last && last[kind] !== undefined && Object.keys(last).length === 1) last[kind] += ch;
	else out.push({ [kind]: ch });
}

/** `before` → `after` as runs of unchanged, removed and added text; removals come before additions. */
export function diffText(before: string, after: string, unit: Unit = 'char'): Piece[] {
	const a = tokens(before, unit);
	const b = tokens(after, unit);
	const width = b.length + 1;
	// lcs[i * width + j]: the common subsequence length of a[i..] and b[j..].
	const lcs = new Uint16Array((a.length + 1) * width);
	for (let i = a.length - 1; i >= 0; i--) {
		for (let j = b.length - 1; j >= 0; j--) {
			lcs[i * width + j] =
				a[i] === b[j] ? lcs[(i + 1) * width + j + 1] + 1 : Math.max(lcs[(i + 1) * width + j], lcs[i * width + j + 1]);
		}
	}
	const out: Piece[] = [];
	let i = 0;
	let j = 0;
	while (i < a.length || j < b.length) {
		if (i < a.length && j < b.length && a[i] === b[j]) {
			push(out, 'same', a[i]);
			i++;
			j++;
		} else if (j >= b.length || (i < a.length && lcs[(i + 1) * width + j] >= lcs[i * width + j + 1])) {
			push(out, 'removed', a[i]);
			i++;
		} else {
			push(out, 'added', b[j]);
			j++;
		}
	}
	return out;
}

const text = (value: unknown): string => (value === undefined || value === null ? '' : String(value));

/** The fields among `names` whose text differs, in `names` order, each with its pieces. */
export function diffFields(
	before: Record<string, unknown>,
	after: Record<string, unknown>,
	names: string[],
	unitOf: (name: string) => Unit = () => 'char'
): { name: string; pieces: Piece[] }[] {
	return names
		.filter((name) => text(before[name]) !== text(after[name]))
		.map((name) => ({ name, pieces: diffText(text(before[name]), text(after[name]), unitOf(name)) }));
}
