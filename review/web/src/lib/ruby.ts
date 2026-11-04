// Furigana for the review site: a port of the matching in the app's FuriganaDictionary.units(for:)
// (Packages/VerbKit/Sources/VerbKit/Furigana/FuriganaDictionary.swift), without its line-break
// chunking, which the browser does itself. Keep the two in step.

export type Segment = { text: string; reading?: string };

/** Characters that may follow a key's kanji part to select its reading. */
const MAX_OKURIGANA_IN_KEY = 3;

/** CJK ideographs plus the iteration mark 々, as FuriganaDictionary.isKanji. */
export function isKanji(ch: string): boolean {
	const code = ch.codePointAt(0) ?? 0;
	return (code >= 0x4e00 && code <= 0x9fff) || code === 0x3005;
}

function isHiragana(ch: string): boolean {
	const code = ch.codePointAt(0) ?? 0;
	return code >= 0x3041 && code <= 0x3096;
}

/**
 * The longest key matching at `start`: its kanji part is any prefix of the kanji run there, and
 * only when it covers the whole run may up to three following hiragana complete the key. The
 * reading belongs to the kanji part only.
 */
function longestMatch(
	chars: string[],
	start: number,
	readings: Record<string, string>
): { kanjiLength: number; reading: string } | undefined {
	let runEnd = start;
	while (runEnd < chars.length && isKanji(chars[runEnd])) runEnd++;
	let best: { total: number; kanjiLength: number; reading: string } | undefined;
	for (let kanjiLength = runEnd - start; kanjiLength >= 1; kanjiLength--) {
		const kanjiEnd = start + kanjiLength;
		// Only hiragana select a reading, so a counter example's whole-run key (何か月) never matches.
		let hiraganaAfter = 0;
		while (
			kanjiEnd + hiraganaAfter < chars.length &&
			hiraganaAfter < MAX_OKURIGANA_IN_KEY &&
			isHiragana(chars[kanjiEnd + hiraganaAfter])
		)
			hiraganaAfter++;
		const maxSuffix = kanjiEnd === runEnd ? hiraganaAfter : 0;
		for (let suffix = maxSuffix; suffix >= 0; suffix--) {
			const key = chars.slice(start, kanjiEnd + suffix).join('');
			const reading = Object.hasOwn(readings, key) ? readings[key] : undefined;
			if (reading === undefined) continue;
			const total = kanjiLength + suffix;
			if (!best || total > best.total) best = { total, kanjiLength, reading };
		}
	}
	return best && { kanjiLength: best.kanjiLength, reading: best.reading };
}

/**
 * `text` as plain and ruby segments. `extra` (an example's own `readings`) is layered over
 * `readings`, as FuriganaDictionary.merging does. Adjacent plain characters form one segment.
 */
export function segments(
	text: string,
	readings: Record<string, string>,
	extra: Record<string, string> = {}
): Segment[] {
	const dictionary = { ...readings, ...extra };
	const chars = Array.from(text);
	const out: Segment[] = [];
	const pushPlain = (s: string) => {
		const last = out.at(-1);
		if (last && last.reading === undefined) last.text += s;
		else out.push({ text: s });
	};
	let i = 0;
	while (i < chars.length) {
		if (isKanji(chars[i])) {
			const match = longestMatch(chars, i, dictionary);
			if (match) {
				out.push({ text: chars.slice(i, i + match.kanjiLength).join(''), reading: match.reading });
				i += match.kanjiLength;
				continue;
			}
		}
		pushPlain(chars[i]);
		i++;
	}
	return out;
}
