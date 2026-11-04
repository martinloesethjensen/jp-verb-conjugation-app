import { afterEach, describe, expect, test, vi } from 'vitest';
import { addUser, ApiError, getMe, listUsers, setActive, setMyName } from './api.ts';

function respond(status: number, body?: unknown) {
	const fetch = vi.fn(async () =>
		body === undefined
			? new Response(null, { status })
			: new Response(JSON.stringify(body), {
					status,
					headers: { 'content-type': 'application/json' }
				})
	);
	vi.stubGlobal('fetch', fetch);
	return fetch;
}

afterEach(() => vi.unstubAllGlobals());

describe('api', () => {
	test('getMe returns the user', async () => {
		const fetch = respond(200, { email: 'a@x.com', display_name: 'A', role: 'reviewer' });
		expect(await getMe()).toEqual({ email: 'a@x.com', display_name: 'A', role: 'reviewer' });
		expect(fetch).toHaveBeenCalledWith('/api/me', expect.objectContaining({ credentials: 'same-origin', redirect: 'manual' }));
	});

	test('a 401 becomes the sign-in message', async () => {
		respond(401, { error: 'sign in first' });
		await expect(getMe()).rejects.toMatchObject({
			status: 401,
			message: 'Your sign-in has expired. Reload the page to sign in again.'
		});
	});

	test('a 403 becomes the no-access message', async () => {
		respond(403, { error: "this account can't do that" });
		const error = await getMe().catch((e) => e);
		expect(error).toBeInstanceOf(ApiError);
		expect(error).toMatchObject({
			status: 403,
			message: "This account can't do that. Ask Martin if you think it should."
		});
	});

	test('other errors use the server text', async () => {
		respond(409, { error: 'that email is already a reviewer' });
		await expect(addUser('ken@example.com', 'Ken')).rejects.toMatchObject({
			status: 409,
			message: 'that email is already a reviewer'
		});
	});

	test('an error without a body uses the fallback', async () => {
		respond(502);
		await expect(listUsers()).rejects.toMatchObject({
			status: 502,
			message: 'Something went wrong. Try again in a minute.'
		});
	});

	test('a network failure uses the fallback', async () => {
		vi.stubGlobal('fetch', vi.fn(async () => Promise.reject(new TypeError('offline'))));
		await expect(getMe()).rejects.toMatchObject({
			status: 0,
			message: 'Something went wrong. Try again in a minute.'
		});
	});

	test('a redirect to the Access sign-in page becomes the sign-in message', async () => {
		const redirected = { ok: false, status: 0, type: 'opaqueredirect', json: async () => undefined };
		vi.stubGlobal('fetch', vi.fn(async () => redirected));
		await expect(getMe()).rejects.toMatchObject({
			status: 401,
			message: 'Your sign-in has expired. Reload the page to sign in again.'
		});
	});

	test('listUsers unwraps the list', async () => {
		const user = { email: 'a@x.com', display_name: 'A', role: 'reviewer', active: true };
		respond(200, { users: [user] });
		expect(await listUsers()).toEqual([user]);
	});

	test('addUser posts JSON to /api/admin/users', async () => {
		const fetch = respond(201, { email: 'ken@example.com', display_name: 'Ken', role: 'reviewer', active: true });
		await addUser('ken@example.com', 'Ken');
		expect(fetch).toHaveBeenCalledWith('/api/admin/users', {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: '{"email":"ken@example.com","display_name":"Ken"}',
			credentials: 'same-origin',
			redirect: 'manual'
		});
	});

	test('setMyName posts to /api/me/name and returns the updated user', async () => {
		const fetch = respond(200, { email: 'a@x.com', display_name: 'Aiko S.', role: 'reviewer' });
		expect((await setMyName('Aiko S.')).display_name).toBe('Aiko S.');
		expect(fetch).toHaveBeenCalledWith('/api/me/name', {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: '{"display_name":"Aiko S."}',
			credentials: 'same-origin',
			redirect: 'manual'
		});
	});

	test('setActive posts to /api/admin/users/active', async () => {
		const fetch = respond(200, { email: 'ken@example.com', display_name: 'Ken', role: 'reviewer', active: false });
		expect((await setActive('ken@example.com', false)).active).toBe(false);
		expect(fetch).toHaveBeenCalledWith('/api/admin/users/active', {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: '{"email":"ken@example.com","active":false}',
			credentials: 'same-origin',
			redirect: 'manual'
		});
	});
});
