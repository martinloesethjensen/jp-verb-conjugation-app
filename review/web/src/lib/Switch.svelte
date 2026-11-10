<script lang="ts">
	// An on/off switch: a checkbox with role="switch", drawn as a pill. Saves through `onchange`.
	let {
		checked,
		label,
		disabled = false,
		onchange
	}: { checked: boolean; label: string; disabled?: boolean; onchange: (on: boolean) => void } = $props();
</script>

<label class="switch">
	<input type="checkbox" role="switch" {checked} {disabled} onchange={(e) => onchange(e.currentTarget.checked)} />
	<span class="track" aria-hidden="true"></span>
	<span class="label">{label}</span>
</label>

<style>
	.switch {
		display: inline-flex;
		align-items: center;
		gap: 0.75rem;
		min-height: 44px;
		cursor: pointer;
	}

	input {
		position: absolute;
		opacity: 0;
		width: 1px;
		height: 1px;
	}

	.track {
		position: relative;
		flex: none;
		width: 2.75rem;
		height: 1.6rem;
		border: 1.5px solid var(--ink);
		border-radius: 999px;
		background: var(--card);
	}

	.track::after {
		content: '';
		position: absolute;
		top: 0.15rem;
		left: 0.15rem;
		width: 1.1rem;
		height: 1.1rem;
		border-radius: 999px;
		background: var(--ink);
	}

	input:checked + .track {
		background: var(--ink);
	}

	input:checked + .track::after {
		left: auto;
		right: 0.15rem;
		background: var(--card);
	}

	input:focus-visible + .track {
		outline: 3px solid var(--ink);
		outline-offset: 2px;
	}

	input:disabled + .track {
		opacity: 0.5;
	}
</style>
