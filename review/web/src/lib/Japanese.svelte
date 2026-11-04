<script lang="ts">
	import { segments } from './ruby.ts';

	let {
		text,
		readings,
		extra = {},
		prose = false
	}: {
		text: string;
		readings: Record<string, string>;
		extra?: Record<string, string>;
		/** Mostly English with some Japanese (descriptions, explanations): ruby, but not set as Japanese. */
		prose?: boolean;
	} = $props();

	const parts = $derived(segments(text, readings, extra));
</script>

<span lang={prose ? undefined : 'ja'}
	>{#each parts as part, i (i)}{#if part.reading}<ruby lang="ja">{part.text}<rt>{part.reading}</rt></ruby
			>{:else}{part.text}{/if}{/each}</span
>
