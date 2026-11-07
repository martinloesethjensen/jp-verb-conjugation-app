// The ids a review-pull wrote, read from the last line of its PR summary
// ("Site suggestion ids: 12, 13. Stamp ids: none."), so the owner marks exactly those as exported.

const list = (text: string | undefined) =>
	!text || text.trim() === 'none'
		? []
		: text
				.split(',')
				.map((n) => Number(n.trim()))
				.filter((n) => Number.isInteger(n) && n > 0);

export function idsFromSummary(text: string): { suggestions: number[]; stamps: number[] } {
	const match = /Site suggestion ids: ([^.]*)\. Stamp ids: ([^.]*)\./.exec(text);
	return { suggestions: list(match?.[1]), stamps: list(match?.[2]) };
}
