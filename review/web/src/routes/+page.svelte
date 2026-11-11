<script lang="ts">
	import { onMount } from 'svelte';
	import { getQueue, getSnapshot, listQueues, type QueueItem, type QueueSummary, type SnapshotFile } from '#lib/api.ts';
	import { replies } from '#lib/replies.svelte.ts';
	import HomeView from '#lib/HomeView.svelte';
	import { MediaQuery } from 'svelte/reactivity';
	import { settings } from '#lib/settings.svelte.ts';
	import { ONBOARDING_PHONE, shouldPhoneWelcome, shouldWelcome } from '#lib/tour.ts';
	import PhoneWelcome from '#lib/PhoneWelcome.svelte';
	import WelcomeDialog from '#lib/WelcomeDialog.svelte';
	import { firstUndone } from '#lib/queue-items.ts';
	import { loadReference } from '#lib/reference.ts';
	import { getSession } from '#lib/session.ts';

	const session = getSession();

	let files = $state<SnapshotFile[] | null>(null);
	let queues = $state<QueueSummary[]>([]);
	let next = $state<QueueItem | undefined>(undefined);
	let readings = $state<Record<string, string>>({});

	/** The Continue card's preview: without it the card simply shows no "Next up". Phones hide the preview
	 * (HomeView's 720px breakpoint), so they skip the fetch. */
	async function loadNext(list: QueueSummary[]) {
		const featured = list.find((q) => q.done < q.total);
		if (!featured || window.matchMedia('(max-width: 720px)').matches) return;
		try {
			const [queue, reference] = await Promise.all([getQueue(featured.id), loadReference()]);
			readings = reference.readings;
			next = firstUndone(queue.items);
		} catch {
			next = undefined;
		}
	}

	onMount(() => {
		getSnapshot()
			.then((list) => (files = list))
			.catch(() => (files = []));
		listQueues()
			.then((list) => {
				queues = list;
				return loadNext(list);
			})
			.catch(() => (queues = []));
	});

	// First sign-in: the welcome on a computer (the tour itself waits for the first queue).
	const phoneWidth = new MediaQuery(ONBOARDING_PHONE);
	const welcoming = $derived(shouldWelcome(settings.value, settings.loaded, phoneWidth.current));
	const phoneWelcoming = $derived(shouldPhoneWelcome(settings.value, settings.loaded, phoneWidth.current));
	const tour = (step: 'welcomed' | 'done') => settings.change({ tour: step }).catch(() => {});
</script>

{#if phoneWelcoming}<PhoneWelcome ondone={() => tour('done')} />{/if}
<WelcomeDialog open={welcoming} onstart={() => tour('welcomed')} onskip={() => tour('done')} />
<HomeView name={session.me().display_name} {queues} {files} {next} {readings} replies={replies.list.filter((r) => r.unread)} />
