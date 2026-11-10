<script lang="ts">
	// The keyboard shortcuts, opened with ? on the queue page or from Settings › Help.
	import Sheet from './Sheet.svelte';
	import { SHORTCUT_HELP } from './shortcuts.ts';

	let { open, onclose }: { open: boolean; onclose: () => void } = $props();
</script>

<Sheet {open} title="Keyboard shortcuts" {onclose}>
	<p class="hint">On the queue page. They're off while you type in a field, except Esc and ⌘Enter.</p>
	<table>
		<tbody>
			{#each SHORTCUT_HELP as [keys, what] (what)}
				<tr>
					<td class="keys">{#each keys as k, i (k)}{#if i}<span class="or"> </span>{/if}<kbd>{k}</kbd>{/each}</td>
					<td>{what}</td>
				</tr>
			{/each}
		</tbody>
	</table>
	<button type="button" class="link" onclick={onclose}>Close</button>
</Sheet>

<style>
	.hint {
		color: var(--muted);
	}

	table {
		width: 100%;
		border-collapse: collapse;
	}

	td {
		padding: 0.4rem 0.5rem;
		border-top: 1px solid var(--rule);
	}

	.keys {
		white-space: nowrap;
		width: 7rem;
	}

	kbd {
		display: inline-block;
		min-width: 1.6rem;
		padding: 0.1rem 0.4rem;
		border: 1px solid var(--rule);
		border-bottom-width: 2px;
		border-radius: var(--radius-input);
		background: var(--card);
		font: inherit;
		font-size: 0.85rem;
		text-align: center;
	}

	.link {
		min-height: 44px;
		margin-top: 0.5rem;
	}
</style>
