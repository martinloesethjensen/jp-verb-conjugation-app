/** WCAG 2 contrast ratio between two `#RRGGBB` colours, from 1 to 21. */
export function contrastRatio(foreground: string, background: string): number {
	const a = luminance(foreground);
	const b = luminance(background);
	const [light, dark] = a > b ? [a, b] : [b, a];
	return (light + 0.05) / (dark + 0.05);
}

function luminance(hex: string): number {
	const match = /^#([0-9a-f]{6})$/i.exec(hex.trim());
	if (!match) throw new Error(`not a #RRGGBB colour: ${hex}`);
	const [r, g, b] = [0, 2, 4].map((i) => {
		const c = parseInt(match[1].slice(i, i + 2), 16) / 255;
		return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
	});
	return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
