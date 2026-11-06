// When the 確認 seal plays its press: only when the viewer's approval has just appeared, and never
// with reduced motion.

export function prefersReducedMotion(): boolean {
	return typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches;
}

/** Whether the seal presses now, given whether it was already pressed. */
export function shouldPress(wasPressed: boolean, pressed: boolean, reducedMotion: boolean): boolean {
	return pressed && !wasPressed && !reducedMotion;
}
