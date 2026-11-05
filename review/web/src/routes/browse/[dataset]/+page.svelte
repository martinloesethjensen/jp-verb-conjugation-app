<script lang="ts">
	import BrowseList from '#lib/BrowseList.svelte';
	import { DATASET_TITLES } from '#lib/labels.ts';
	import type { PageProps } from './$types';

	let { data }: PageProps = $props();
</script>

<svelte:head>
	<title>{DATASET_TITLES[data.dataset]} · Kotoba Table review</title>
</svelte:head>

{#key data.dataset}
	<BrowseList dataset={data.dataset} />
{/key}
