import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const PROJECT_URL = Deno.env.get("PROJECT_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SERVICE_ROLE_KEY")!;
const SENDGRID_API_KEY = Deno.env.get("SENDGRID_API_KEY");
const FCM_SERVICE_ACCOUNT = Deno.env.get("FCM_SERVICE_ACCOUNT");
const FCM_PROJECT_ID = Deno.env.get("FCM_PROJECT_ID");
const FCM_SERVER_KEY = Deno.env.get("FCM_SERVER_KEY");

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json",
};

const getErrorMessage = (e: unknown) => {
  if (e instanceof Error) return e.message;
  if (typeof e === 'string') return e;
  return JSON.stringify(e);
};

const base64UrlEncode = (data: Uint8Array) => {
  const base64 = btoa(String.fromCharCode(...data));
  return base64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
};

const pemToArrayBuffer = (pem: string) => {
  const cleaned = pem.replace(/-----BEGIN PRIVATE KEY-----/, '').replace(/-----END PRIVATE KEY-----/, '').replace(/\s+/g, '');
  const binary = atob(cleaned);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
};

const importPrivateKey = async (pem: string) => {
  return await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(pem),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
};

const signJwt = async (payload: Record<string, unknown>, privateKeyPem: string) => {
  const encoder = new TextEncoder();
  const header = { alg: 'RS256', typ: 'JWT' };
  const encodedHeader = base64UrlEncode(encoder.encode(JSON.stringify(header)));
  const encodedPayload = base64UrlEncode(encoder.encode(JSON.stringify(payload)));
  const data = `${encodedHeader}.${encodedPayload}`;
  const key = await importPrivateKey(privateKeyPem);
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, encoder.encode(data));
  return `${data}.${base64UrlEncode(new Uint8Array(signature))}`;
};

let cachedAccessToken: string | null = null;
let cachedAccessTokenExpiresAt = 0;

const getGoogleAccessToken = async () => {
  if (!FCM_SERVICE_ACCOUNT || !FCM_PROJECT_ID) {
    throw new Error('Missing FCM_SERVICE_ACCOUNT or FCM_PROJECT_ID');
  }

  const now = Math.floor(Date.now() / 1000);
  if (cachedAccessToken && now < cachedAccessTokenExpiresAt - 60) {
    return cachedAccessToken;
  }

  const key = JSON.parse(FCM_SERVICE_ACCOUNT);
  const assertion = await signJwt(
    {
      iss: key.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    },
    key.private_key,
  );

  const response = await fetch('https://oauth2.googleapis.com/token', {
  method: 'POST',
  headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
  body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${encodeURIComponent(assertion)}`,
});

  const data = await response.json();
  if (!response.ok) {
    throw new Error(`Google auth failed: ${response.status} ${JSON.stringify(data)}`);
  }

  cachedAccessToken = data.access_token;
  cachedAccessTokenExpiresAt = now + (data.expires_in || 3600);
  return cachedAccessToken;
};

const sendFcmMessage = async (token: string, title: string, body: string, data: unknown) => {
  // Clean data for FCM (flat key-value pairs of strings only)
  const cleanData: Record<string, string> = {};
  if (data && typeof data === 'object') {
    for (const [key, value] of Object.entries(data)) {
      if (typeof value === 'string') {
        cleanData[key] = value;
      } else if (value !== null && value !== undefined) {
        cleanData[key] = JSON.stringify(value);
      }
    }
  }

  if (FCM_SERVICE_ACCOUNT && FCM_PROJECT_ID) {
    const accessToken = await getGoogleAccessToken();
    const response = await fetch(
  `https://fcm.googleapis.com/v1/projects/${FCM_PROJECT_ID}/messages:send`,
  {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data: cleanData,
          webpush: {
            notification: {
              icon: '/icons/Icon-192.png',
              badge: '/icons/Icon-96.png',
              requireInteraction: true,
            },
            fcmOptions: {
              link: cleanData.type === 'live_lesson' 
                ? `/lesson/${cleanData.lesson_id || cleanData.id || ''}` 
                : cleanData.type === 'chat_message' 
                  ? `/chat/${cleanData.session_id || ''}` 
                  : '/'
            }
          }
        },
      }),
    });
    return response;
  }

  if (!FCM_SERVER_KEY) {
    throw new Error('No push credentials configured');
  }

  return await fetch('https://fcm.googleapis.com/fcm/send', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `key=${FCM_SERVER_KEY}`,
    },
    body: JSON.stringify({
      to: token,
      notification: { title, body },
      data: cleanData,
    }),
  });
};

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const { notificationId } = await req.json();
    if (!notificationId) {
      return new Response(JSON.stringify({ success: false, error: 'Missing notificationId' }), { status: 400, headers: corsHeaders });
    }

    const supabase = createClient(PROJECT_URL, SERVICE_ROLE_KEY);

    const { data: notification, error: fetchError } = await supabase
  .from('notifications')
  .select('*, profiles(id, email, full_name)') // <-- REMOVED fcm_tokens
  .eq('id', notificationId)
  .maybeSingle();

    if (fetchError) throw fetchError;
    if (!notification) {
      return new Response(JSON.stringify({ success: false, error: 'Notification not found' }), { status: 404, headers: corsHeaders });
    }

    const user = notification.profiles;
    const channels: string[] = notification.channels || ['in_app'];
    const results: any = { notificationId };

    if (channels.includes('email') && SENDGRID_API_KEY && user?.email) {
      try {
        const sgResp = await fetch('https://api.sendgrid.com/v3/mail/send', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${SENDGRID_API_KEY}`,
          },
          body: JSON.stringify({
            personalizations: [{ to: [{ email: user.email, name: user.full_name || '' }] }],
            from: { email: 'no-reply@afrinova.academy', name: 'AfriNova' },
            subject: notification.title,
            content: [{ type: 'text/plain', value: notification.body || '' }],
          }),
        });
        results.email = { status: sgResp.status };
      } catch (e) {
        results.email = { error: getErrorMessage(e) };
      }
    }

    if (channels.includes('push')) {
      const { data: devices, error: devicesError } = await supabase
        .from('user_devices')
        .select('token')
        .eq('user_id', user?.id);

      if (devicesError) throw devicesError;

      const tokens = Array.isArray(devices) ? devices.map((d: any) => d.token).filter(Boolean) : [];
     
      if (tokens.length > 0) {
        const pushResults: any[] = [];
        for (const token of tokens) {
          try {
            // FIX: Restored correct positional arguments: token, title, body, data
            const resp = await sendFcmMessage(
              token, 
              notification.title, 
              notification.body || '', 
              {
                ...notification.data,
                type: notification.type,
                notification_id: notification.id
              }
            );

            // Housekeeping: remove expired tokens from DB dynamically
            if (resp.status === 404 || resp.status === 410) {
              await supabase.from('user_devices').delete().eq('token', token);
            }

            pushResults.push({ token: token.substring(0, 15) + '...', status: resp.status });
          } catch (e) {
            pushResults.push({ token: token.substring(0, 15) + '...', error: getErrorMessage(e) });
          }
        }
        results.push = pushResults;
      } else {
        results.push = { error: 'No device tokens found' };
      }
    }

    // Mark as delivered
    try {
      await supabase.from('notifications').update({ delivered_at: new Date().toISOString() }).eq('id', notificationId);
    } catch (_) {}

    return new Response(JSON.stringify({ success: true, results }), { headers: corsHeaders });
  } catch (error) {
    return new Response(JSON.stringify({ success: false, error: getErrorMessage(error) }), { status: 500, headers: corsHeaders });
  }
});
