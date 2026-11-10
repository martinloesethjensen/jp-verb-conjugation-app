<script lang="ts">
	// The Account page became Settings; old links and bookmarks land there.
	import { onMount } from 'svelte';

	onMount(() => location.replace('/settings'));
</script>

<svelte:head>
	<title>Settings · Kotoba Table review</title>
</svelte:head>

<p>Your name and credit are in <a href="/settings">Settings</a> now.</p>
