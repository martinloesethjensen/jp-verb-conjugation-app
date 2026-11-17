<script lang="ts">
	// What someone's access role lets them do on the site.
	import type { Role } from './api.ts';

	let { role }: { role: Role } = $props();

	const SUMMARY: Record<Role, string> = {
		reviewer: 'Reviewer: you approve items, suggest changes, leave notes and reply.',
		native:
			"Native speaker: you also accept or decline other people's changes to Japanese fields.",
		teacher: "Teacher: you also accept or decline other people's suggestions.",
		admin: 'Owner: you also manage reviewers, queues, stamps and exports.'
	};
</script>

<p class="role">{SUMMARY[role]}</p>

<style>
	.role {
		margin: 0;
	}
</style>
