export async function handleAuth(request: Request, env: Env): Promise<Response | null> {
  const authorization = request.headers.get('Authorization');
  
  if (!authorization) {
    return new Response('Unauthorized', {
      status: 401,
      headers: {
        'WWW-Authenticate': 'Basic realm="Feral File Distribution"',
      },
    });
  }

  const [scheme, encoded] = authorization.split(' ');
  if (!encoded || scheme !== 'Basic') {
    return new Response('Malformed authorization header', { status: 400 });
  }

  const buffer = Uint8Array.from(atob(encoded), (character) => character.charCodeAt(0));
  const decoded = new TextDecoder().decode(buffer).normalize();
  const [username, password] = decoded.split(':');

  if (username !== env.AUTH_USERNAME || password !== env.AUTH_PASSWORD) {
    return new Response('Invalid credentials', { status: 401 });
  }

  return null;
} 