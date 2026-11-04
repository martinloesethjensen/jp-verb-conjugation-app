import adapter from '@sveltejs/adapter-static';
import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vitest/config';
import { mockApi } from './src/dev/mock-api.ts';

export default defineConfig({
	plugins: [
		// Only `vite dev` uses it, so the build can't contain it. The Worker has no sign-in bypass.
		mockApi(),
		sveltekit({
			compilerOptions: {
				// Force runes mode for the project, except for libraries. Can be removed in svelte 6.
				runes: ({ filename }) =>
					filename.split(/[/\\]/).includes('node_modules') ? undefined : true
			},
			// Cloudflare Pages serves the prerendered pages; the Worker answers /api/* on the same hostname.
			adapter: adapter({ pages: 'build', assets: 'build', fallback: undefined, strict: true }),
			// Prerendered pages get this as a <meta> tag with hashes for SvelteKit's own inline script.
			// No 'unsafe-inline' for styles either, so components use classes only: no style="", no style:,
			// no transitions. frame-ancestors can't go in a <meta>; static/_headers sends it.
			csp: {
				mode: 'hash',
				directives: {
					'default-src': ['self'],
					'script-src': ['self'],
					'style-src': ['self', 'https://fonts.googleapis.com'],
					'font-src': ['https://fonts.gstatic.com'],
					'img-src': ['self', 'data:'],
					'connect-src': ['self'],
					'base-uri': ['none'],
					'form-action': ['self'],
					'object-src': ['none']
				}
			}
		})
	],
	test: {
		include: ['src/**/*.test.ts'],
		environment: 'node'
	}
});
