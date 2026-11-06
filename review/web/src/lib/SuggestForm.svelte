<script lang="ts">
	// The form for suggesting a change to one target, drawn from the Worker's field table. Ids and the
	// spellings they are built from aren't fields here, so they can't change. A live preview shows the
	// result in the card style, and kanji without furigana ask for a reading.
	import { untrack } from 'svelte';
	import { isStale, problem, type Field } from './api.ts';
	import ErrorLine from './ErrorLine.svelte';
	import Japanese from './Japanese.svelte';
	import Sentence from './Sentence.svelte';
	import { choiceLabel, fieldLabel, JAPANESE_FIELDS } from './labels.ts';
	import { unknownKanjiRuns } from './targets.ts';

	type Json = { [key: string]: any };

	let {
		fields,
		current,
		initial = current,
		readings,
		forms,
		extra = {},
		submitLabel = 'Send suggestion',
		hint = "Spelling and ids can't change here. Leave a note for Martin if they're wrong.",
		conflictIsStale = true,
		onsubmit,
		oncancel
	}: {
		fields: Field[];
		/** The target as it is now; edits are what differ from it. */
		current: Json;
		/** What the inputs start with (the proposal, when the owner edits one). */
		initial?: Json;
		readings: Record<string, string>;
		forms: Record<string, string>;
		/** The example's own readings, for the preview. */
		extra?: Record<string, string>;
		submitLabel?: string;
		/** The quiet line under the fields. */
		hint?: string;
		/** A 409 means the item changed (offer a reload); false where it means a duplicate. */
		conflictIsStale?: boolean;
		onsubmit: (edits: Record<string, string>, furigana: Record<string, string>) => Promise<void>;
		oncancel: () => void;
	} = $props();

	const uid = $props.id();
	const text = (value: unknown) => (value === undefined || value === null ? '' : String(value));
	let values = $state<Record<string, string>>(
		untrack(() => Object.fromEntries(fields.map((f) => [f.name, text(initial[f.name])])))
	);
	let answers = $state<Record<string, string>>({});
	let busy = $state(false);
	let failure = $state<string | null>(null);
	let stale = $state(false);

	const edits = $derived(
		Object.fromEntries(
			fields
				.filter((f) => values[f.name].trim() !== text(current[f.name]))
				.map((f) => [f.name, values[f.name].trim()])
		)
	);
	const runs = $derived(
		[...new Set(fields.filter((f) => JAPANESE_FIELDS.has(f.name)).flatMap((f) => unknownKanjiRuns(values[f.name], readings)))]
	);
	const furigana = $derived(
		Object.fromEntries(runs.filter((run) => answers[run]?.trim()).map((run) => [run, answers[run].trim()]))
	);
	const proposed = $derived({ ...current, ...values });
	const isSentence = $derived(fields.some((f) => f.name === 'jp') && fields.some((f) => f.name === 'en'));

	async function submit(event: SubmitEvent) {
		event.preventDefault();
		if (!Object.keys(edits).length) {
			failure = 'nothing changed';
			stale = false;
			return;
		}
		busy = true;
		failure = null;
		try {
			await onsubmit(edits, furigana);
		} catch (error) {
			failure = problem(error);
			stale = conflictIsStale && isStale(error);
		} finally {
			busy = false;
		}
	}
</script>

<form class="suggest" onsubmit={submit}>
	{#each fields as field (field.name)}
		<label for="{uid}-{field.name}">{fieldLabel(field.name)}{field.optional ? ' (optional)' : ''}</label>
		{#if field.input === 'long'}
			<textarea id="{uid}-{field.name}" rows="4" maxlength="2000" bind:value={values[field.name]}></textarea>
		{:else if field.input === 'form'}
			<select id="{uid}-{field.name}" bind:value={values[field.name]}>
				{#if !values[field.name]}<option value="" disabled>Choose…</option>{/if}
				{#each Object.entries(forms) as [id, label] (id)}<option value={id}>{label}</option>{/each}
				{#if values[field.name] && !(values[field.name] in forms)}<option value={values[field.name]}>{values[field.name]}</option>{/if}
			</select>
		{:else if field.input === 'choice' || field.input === 'jlpt'}
			<select id="{uid}-{field.name}" bind:value={values[field.name]}>
				{#if field.optional}<option value="">None</option>
				{:else if !values[field.name]}<option value="" disabled>Choose…</option>{/if}
				{#each field.choices as choice (choice)}<option value={choice}>{choiceLabel(field.name, choice)}</option>{/each}
			</select>
		{:else}
			<input
				id="{uid}-{field.name}"
				maxlength={field.input === 'slug' ? 40 : 2000}
				lang={JAPANESE_FIELDS.has(field.name) || field.input === 'kana' ? 'ja' : undefined}
				placeholder={field.input === 'kana' ? 'in kana' : field.input === 'slug' ? 'like hon or te-iru' : undefined}
				autocapitalize={field.input === 'slug' ? 'none' : undefined}
				bind:value={values[field.name]}
			/>
		{/if}
	{/each}

	{#each runs as run (run)}
		<label for="{uid}-reading-{run}">How is <span lang="ja">{run}</span> read?</label>
		<input id="{uid}-reading-{run}" lang="ja" placeholder="in hiragana" bind:value={answers[run]} />
	{/each}

	<p class="quiet">{hint}</p>

	<div class="preview" aria-label="Preview">
		{#if isSentence}
			<Sentence jp={proposed.jp} en={proposed.en} {readings} extra={{ ...extra, ...furigana }} />
		{:else}
			{#each fields as field (field.name)}
				{#if values[field.name].trim()}
					<p>
						<span class="quiet">{fieldLabel(field.name)}:</span>
						{#if JAPANESE_FIELDS.has(field.name)}<Japanese text={values[field.name]} readings={{ ...readings, ...furigana }} />
						{:else}{field.input === 'choice' ? choiceLabel(field.name, values[field.name]) : values[field.name]}{/if}
					</p>
				{/if}
			{/each}
		{/if}
	</div>

	<div class="buttons">
		<button class="primary" disabled={busy}>{submitLabel}</button>
		<button type="button" class="link" onclick={oncancel}>Cancel</button>
	</div>
	<ErrorLine message={failure} {stale} />
</form>

<style>
	.suggest {
		display: grid;
		gap: 0.3rem;
		margin-top: 0.75rem;
		padding: 0.9rem 1rem;
		border: 1px dashed var(--rule);
		border-radius: var(--radius);
	}

	label {
		margin-top: 0.4rem;
		font-size: 0.9rem;
	}

	.quiet {
		margin: 0.5rem 0 0;
		font-size: 0.85rem;
		color: var(--muted);
	}

	.preview {
		margin-top: 0.5rem;
		padding: 0.25rem 0.9rem;
		background: var(--paper);
		border-radius: var(--radius);
	}

	.preview p {
		margin: 0.4rem 0;
	}

	.preview :global(rt) {
		font-size: 0.5em;
		color: var(--muted);
	}

	.buttons {
		display: flex;
		gap: 0.75rem;
		align-items: center;
		margin-top: 0.5rem;
	}
</style>
