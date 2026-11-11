<script lang="ts">
	// Working through one queue, one item at a time. On a laptop the queue's items sit in a list beside
	// the card. The address is /queue?id=…, read once the page is in the browser.
	import { onMount } from 'svelte';
	import { MediaQuery } from 'svelte/reactivity';
	import { page } from '$app/state';
	import { getItem, getQueue, problem, skip, type Dataset, type Field, type Queue, type QueueItem } from '#lib/api.ts';
	import Progress from '#lib/Progress.svelte';
	import ReviewCard from '#lib/ReviewCard.svelte';
	import Sheet from '#lib/Sheet.svelte';
	import QueueItemList from '#lib/QueueItemList.svelte';
	import KeyboardHelp from '#lib/KeyboardHelp.svelte';
	import { filterItems, firstUndone, keyOf, type ItemFilter } from '#lib/queue-items.ts';
	import { loadReference } from '#lib/reference.ts';
	import { EntryReview } from '#lib/review.svelte.ts';
	import { settings } from '#lib/settings.svelte.ts';
	import { isTyping, sendButton, shortcutFor } from '#lib/shortcuts.ts';
	import TourGuide from '#lib/TourGuide.svelte';
	import { availableSteps, ONBOARDING_PHONE, shouldTour, type TourStep } from '#lib/tour.ts';

	type Json = { [key: string]: any };
	type Loaded = { entry: Json | null; review: EntryReview };

	let queueId = 0;
	let data = $state<Queue | null>(null);
	let failure = $state<string | null>(null);
	let selected = $state<string | null>(null);
	let filter = $state<ItemFilter>('all');
	let readings = $state<Record<string, string>>({});
	let forms = $state<Record<string, string>>({});
	let fieldTable = $state<Record<string, Field[]>>({});
	let itemsOpen = $state(false);

	// Below 960px the list moves into the Items sheet; crossing back closes it.
	const phone = new MediaQuery(ONBOARDING_PHONE);
	$effect(() => {
		if (!phone.current) itemsOpen = false;
	});

	function choose(item: QueueItem) {
		selected = keyOf(item);
		itemsOpen = false;
	}

	const current = $derived(
		data ? (data.items.find((i) => keyOf(i) === selected) ?? firstUndone(data.items)) : undefined
	);

	// Entries fetched in this visit, so moving between parts of one entry doesn't fetch it again.
	const entries = new Map<string, Promise<Loaded>>();
	function entryFor(item: QueueItem): Promise<Loaded> {
		const key = `${item.dataset}/${item.entry_id}`;
		let pending = entries.get(key);
		if (!pending) {
			const review = new EntryReview(item.dataset, item.entry_id);
			pending = Promise.all([
				getItem(item.dataset as Dataset, item.entry_id)
					.then((r) => r.item as Json)
					.catch(() => null),
				review.load()
			]).then(([entry]) => ({ entry, review }));
			entries.set(key, pending);
		}
		return pending;
	}

	onMount(() => {
		queueId = Number(page.url.searchParams.get('id'));
		if (!queueId) {
			failure = 'This link is missing which queue to show.';
			return;
		}
		refresh();
		loadReference().then((reference) => {
			readings = reference.readings;
			forms = reference.forms;
			fieldTable = reference.fields;
		});
	});

	async function refresh() {
		try {
			data = await getQueue(queueId);
		} catch (error) {
			failure = problem(error);
		}
	}

	/** After an action the next undone item comes up. */
	async function next() {
		selected = null;
		await refresh();
	}

	/** After approving or undoing in place: keep this item on screen and refresh the list and count. */
	async function changed() {
		if (current) selected = keyOf(current);
		await refresh();
	}

	async function skipCurrent(item: QueueItem) {
		data = await skip(queueId, { dataset: item.dataset, kind: item.kind, id: item.item_id });
		selected = null;
	}

	// The tour's highlighted steps, the first time someone who saw the welcome opens a queue. They wait for the
	// card to render, then use whichever targets are on the page.
	let tourSteps = $state<TourStep[] | null>(null);
	$effect(() => {
		if (tourSteps || !current || !shouldTour(settings.value, settings.loaded, phone.current)) return;
		let frames = 0;
		let handle = requestAnimationFrame(function look() {
			if (document.querySelector('[data-tour="item"]') || ++frames > 300) {
				tourSteps = availableSteps((t) => document.querySelector(`[data-tour="${t}"]`) !== null);
			} else handle = requestAnimationFrame(look);
		});
		return () => cancelAnimationFrame(handle);
	});

	function endTour() {
		tourSteps = [];
		settings.change({ tour: 'done' }).catch(() => {});
	}

	// Keyboard shortcuts (desktop, unless switched off in Settings): a key presses the button that carries its
	// `data-shortcut` in the current card, so it only ever does what the card offers.
	let pane = $state<HTMLElement>();
	let helpOpen = $state(false);

	const usable = (el: HTMLElement) =>
		el.getClientRects().length > 0 && !(el as HTMLButtonElement).disabled;

	function move(step: 1 | -1) {
		if (!data || !current) return;
		const list = filterItems(data.items, filter);
		const at = list.findIndex((i) => keyOf(i) === keyOf(current!));
		const to = list[at + step];
		if (to) choose(to);
	}

	function onkeydown(event: KeyboardEvent) {
		if (phone.current || !settings.value.shortcuts_on || !data || event.defaultPrevented) return;
		const action = shortcutFor(event, isTyping(event.target));
		if (!action) return;
		if (action === 'help') {
			event.preventDefault();
			helpOpen = true;
			return;
		}
		if (helpOpen) return;
		if (action === 'next' || action === 'previous') {
			event.preventDefault();
			move(action === 'next' ? 1 : -1);
			return;
		}
		if (action === 'send') {
			const button = sendButton((event.target as HTMLElement | null)?.closest?.('form') ?? null);
			if (button) {
				event.preventDefault();
				button.click();
			}
			return;
		}
		const target = [...(pane?.querySelectorAll<HTMLElement>(`[data-shortcut="${action}"]`) ?? [])].find(usable);
		if (!target) return;
		event.preventDefault();
		if (action === 'reply') target.focus();
		else target.click();
	}

</script>

<svelte:window {onkeydown} />
{#if tourSteps?.length && shouldTour(settings.value, settings.loaded, phone.current)}
	<TourGuide steps={tourSteps} ondone={endTour} />
{/if}
<KeyboardHelp open={helpOpen} onclose={() => (helpOpen = false)} />

<svelte:head>
	<title>{data?.queue.title ?? 'Queue'} · Kotoba Table review</title>
</svelte:head>

{#if failure}
	<p class="notice" role="alert">{failure}</p>
{:else if !data}
	<p class="quiet">Loading…</p>
{:else}
	<header class="queue-header">
		<div class="heading">
			<p class="back">
				<a href="/"
					><svg class="chevron" viewBox="0 0 16 16" aria-hidden="true"><path d="M10 3L5 8l5 5" /></svg>Home</a
				>
			</p>
			<h1>{data.queue.title}</h1>
			{#if data.queue.description}<p class="quiet">{data.queue.description}</p>{/if}
		</div>
		<div class="progress-block">
			<p class="count"><strong>{data.queue.done}</strong> of {data.queue.total} done</p>
			<Progress total={data.queue.total} done={data.queue.done} flagged={data.queue.with_suggestion} />
			{#if data.queue.with_suggestion}
				<p class="flagged"><span class="red-dot" aria-hidden="true"></span>{data.queue.with_suggestion} with suggestions</p>
			{/if}
			<button type="button" class="items-button" aria-haspopup="dialog" onclick={() => (itemsOpen = true)}
				><svg class="list-icon" viewBox="0 0 16 16" aria-hidden="true"><path d="M5 4h8M5 8h8M5 12h8M2.5 4h.01M2.5 8h.01M2.5 12h.01" /></svg
				>Items</button
			>
		</div>
	</header>

	<Sheet open={itemsOpen} title="{data.items.length} items" onclose={() => (itemsOpen = false)}>
		<QueueItemList items={data.items} currentKey={current && keyOf(current)} bind:filter onselect={choose} />
	</Sheet>

	<div class="layout">
		<nav class="list card" aria-label="Items in this queue" data-tour="list">
			<QueueItemList items={data.items} currentKey={current && keyOf(current)} bind:filter onselect={choose} />
		</nav>

		<div class="card-pane" bind:this={pane}>
			{#if current}
				{#key keyOf(current)}
					{#await entryFor(current)}
						<p class="quiet">Loading…</p>
					{:then loaded}
						<ReviewCard
							item={current}
							entry={loaded.entry}
							review={loaded.review}
							fields={fieldTable[`${current.dataset}/${current.kind}`] ?? []}
							{readings}
							{forms}
							onaction={next}
							onnext={next}
							onchange={changed}
							docked
							onskip={() => skipCurrent(current)}
						/>
					{:catch error}
						<p class="notice" role="alert">{problem(error)}</p>
					{/await}
				{/key}
			{:else}
				<section class="finished">
					<p class="lead">That's everything in this queue. Thank you!</p>
					<p><a href="/">Back home</a></p>
				</section>
			{/if}
		</div>
	</div>
{/if}

<style>
	.queue-header {
		display: flex;
		flex-wrap: wrap;
		justify-content: space-between;
		align-items: flex-end;
		gap: 1rem 3rem;
		margin-bottom: 2rem;
	}

	.heading {
		flex: 1 1 28rem;
		min-width: 0;
		overflow-wrap: anywhere;
	}

	.back {
		margin: 0 0 0.75rem;
	}

	.back a {
		display: inline-flex;
		align-items: center;
		gap: 0.25rem;
		min-height: 44px;
		color: var(--muted);
		text-decoration: none;
	}

	.back a:hover {
		color: var(--ink);
	}

	.chevron {
		width: 16px;
		height: 16px;
		fill: none;
		stroke: currentColor;
		stroke-width: 1.8;
		stroke-linecap: round;
		stroke-linejoin: round;
	}

	h1 {
		margin: 0;
	}

	.heading .quiet {
		margin: 0.5rem 0 0;
	}

	.progress-block {
		flex: 0 1 16rem;
		display: grid;
		gap: 0.4rem;
	}

	.progress-block p {
		margin: 0;
	}

	.count strong {
		font-size: 1.4rem;
	}

	.flagged {
		display: flex;
		align-items: center;
		gap: 0.4rem;
		font-size: 0.9rem;
		color: var(--muted);
	}

	.items-button {
		justify-self: start;
		margin-top: 0.4rem;
	}

	.list-icon {
		width: 16px;
		height: 16px;
		fill: none;
		stroke: currentColor;
		stroke-width: 1.8;
		stroke-linecap: round;
	}

	@media (min-width: 960px) {
		.items-button {
			display: none;
		}
	}

	.red-dot {
		width: 0.5rem;
		height: 0.5rem;
		border-radius: 50%;
		background: var(--red);
	}

	.quiet {
		color: var(--muted);
	}

	.layout {
		display: grid;
		gap: 1.5rem;
		max-width: 46rem;
	}

	/* Phones get the card alone; laptops get the list beside it. */
	.list {
		display: none;
	}

	@media (min-width: 960px) {
		.layout {
			grid-template-columns: 19rem minmax(0, 1fr);
			max-width: none;
			align-items: start;
		}

		.list {
			display: block;
			position: sticky;
			top: 1rem;
			max-height: calc(100vh - 2rem);
			overflow-y: auto;
			padding: 0.75rem;
		}
	}
















	/* The next card slides in from the right; clip it so a phone never scrolls sideways meanwhile. */
	.card-pane {
		min-width: 0;
		overflow-x: clip;
		overflow-clip-margin: 8px;
	}

	/* Room under the card for the fixed action bar, so it never covers the last suggestion. */
	@media (max-width: 959px) {
		.card-pane {
			padding-bottom: calc(9rem + env(safe-area-inset-bottom));
		}
	}


	.finished {
		padding: 1.5rem;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
	}

	.lead {
		margin-top: 0;
		font-size: 1.15rem;
		font-weight: 500;
	}

	.notice {
		max-width: 34rem;
		padding: 0.75rem 1rem;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
	}
</style>
