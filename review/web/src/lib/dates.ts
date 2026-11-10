/** A short date: day and month, plus the year when it isn't `now`'s year. */
export function shortDate(date: Date, now = new Date(), locale?: string): string {
	return date.toLocaleDateString(locale, {
		day: 'numeric',
		month: 'short',
		...(date.getFullYear() === now.getFullYear() ? {} : { year: 'numeric' })
	});
}
