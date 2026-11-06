<script lang="ts">
	// The end of a list on the item page: suggestions to add to it, and the button that opens the add form.
	import type { Field } from './api.ts';
	import SuggestForm from './SuggestForm.svelte';
	import SuggestionCard from './SuggestionCard.svelte';
	import { ADD_LABELS, ADD_NOTE } from './labels.ts';
	import type { EntryReview } from './review.svelte.ts';

	let {
		review,
		kind,
		parentKind,
		parentId,
		fields,
		readings,
		forms
	}: {
		review: EntryReview;
		/** What is added: `example`, `usage`… */
		kind: string;
		/** Where it goes: the entry, a usage or a pitfall. */
		parentKind: string;
		parentId: string;
		fields: Field[];
		readings: Record<string, string>;
		forms: Record<string, string>;
	} = $props();

	let open = $state(false);

	const pending = $derived(review.additionsUnder(parentKind, parentId, kind));
	const defaults = $derived(Object.fromEntries(fields.filter((f) => f.default).map((f) => [f.name, f.default])));
	const names = $derived(fields.map((f) => f.name));
</script>

{#each pending as s (s.id)}
	<SuggestionCard
		suggestion={s}
		current={null}
		{names}
		{readings}
		{forms}
		onwithdraw={() => review.withdraw(s.id)}
		oncomment={(text) => review.comment(s.id, text)}
	/>
{/each}

{#if fields.length}
	<div class="add-part">
		{#if open}
			<SuggestForm
				{fields}
				current={{}}
				initial={defaults}
				{readings}
				{forms}
				submitLabel="Suggest adding it"
				hint={ADD_NOTE}
				onsubmit={async (values, furigana) => {
					await review.add(kind, parentKind, parentId, values, {
						furigana: Object.keys(furigana).length ? furigana : undefined
					});
					open = false;
				}}
				oncancel={() => (open = false)}
			/>
		{:else}
			<button type="button" class="link add" onclick={() => (open = true)}>
				{ADD_LABELS[`${review.dataset}/${kind}`] ?? 'Add one'}
			</button>
		{/if}
	</div>
{/if}

<style>
	.add-part {
		margin-top: 0.5rem;
	}
</style>
