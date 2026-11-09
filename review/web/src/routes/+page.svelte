<script lang="ts">
	import { onMount } from 'svelte';
	import { getSnapshot, listQueues, type QueueSummary, type SnapshotFile } from '#lib/api.ts';
	import HomeView from '#lib/HomeView.svelte';
	import { getSession } from '#lib/session.ts';

	const session = getSession();

	let files = $state<SnapshotFile[] | null>(null);
	let queues = $state<QueueSummary[]>([]);

	onMount(() => {
		getSnapshot()
			.then((list) => (files = list))
			.catch(() => (files = []));
		listQueues()
			.then((list) => (queues = list))
			.catch(() => (queues = []));
	});
</script>

<HomeView name={session.me().display_name} {queues} {files} next={undefined} readings={{}} />
