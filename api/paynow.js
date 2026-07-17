export default async function handler(req, res) {
  // CORS headers
  const origin = req.headers.origin || '*';
  res.setHeader('Access-Control-Allow-Origin', origin);
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.setHeader('Access-Control-Max-Age', '86400');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  // Handle both initiate and poll
  const url = new URL(req.url, `https://${req.headers.host}`);
  const action = url.searchParams.get('action');

  try {
    if (action === 'poll') {
      return await handlePoll(req, res);
    } else {
      return await handleInitiate(req, res);
    }
  } catch (error) {
    console.error('Server Error:', error);
    return res.status(500).json({ 
      success: false, 
      error: 'Payment service temporarily unavailable' 
    });
  }
}

async function handleInitiate(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ 
      success: false, 
      error: 'Method not allowed' 
    });
  }

  const { reference, amount, mobileNumber, email } = req.body;
  
  if (!reference || !amount || !mobileNumber) {
    return res.status(400).json({ 
      success: false, 
      error: 'Missing required fields' 
    });
  }

  const amountStr = Number(amount).toFixed(2);
  const autoEmail = email?.trim() || `${mobileNumber}@mobile.paynow.co.zw`;
  const integrationId = process.env.PAYNOW_INTEGRATION_ID;
  const integrationKey = process.env.PAYNOW_INTEGRATION_KEY;

  if (!integrationId || !integrationKey) {
    console.error('PayNow credentials not configured');
    return res.status(500).json({ 
      success: false, 
      error: 'Payment gateway not configured' 
    });
  }

  // CORRECT ORDER for mobile payments
  const items = {
    id: integrationId,
    reference: reference,
    amount: amountStr,
    authemail: autoEmail,
    additionalinfo: '',
    returnurl: 'https://afrinova-academy.com/payment/complete',
    resulturl: 'https://rwheufzhixqqifoleltu.supabase.co/functions/v1/paynow-webhook',
    status: 'Message',
    phone: mobileNumber.trim(),
    method: 'ecocash'
  };

  // Concatenate values in CORRECT ORDER
  const concatString = 
    items.id +
    items.reference +
    items.amount +
    items.authemail +
    items.additionalinfo +
    items.returnurl +
    items.resulturl +
    items.status +
    items.phone +
    items.method;

  // Generate hash
  const stringToHash = concatString + integrationKey;
  const crypto = require('crypto');
  const hash = crypto.createHash('sha512').update(stringToHash).digest('hex').toUpperCase();

  // Build form data
  const formData = new URLSearchParams();
  formData.append('id', items.id);
  formData.append('reference', items.reference);
  formData.append('amount', items.amount);
  formData.append('authemail', items.authemail);
  formData.append('additionalinfo', items.additionalinfo);
  formData.append('returnurl', items.returnurl);
  formData.append('resulturl', items.resulturl);
  formData.append('status', items.status);
  formData.append('phone', items.phone);
  formData.append('method', items.method);
  formData.append('hash', hash);

  console.log('Initiating PayNow payment...');

  const paynowResponse = await fetch('https://www.paynow.co.zw/interface/remotetransaction', {
    method: 'POST',
    headers: { 
      'Content-Type': 'application/x-www-form-urlencoded',
      'User-Agent': 'AfriNova-Academy/1.0'
    },
    body: formData.toString(),
  });

  const responseText = await paynowResponse.text();
  console.log('PayNow Response:', responseText);
  
  // Parse response
  const lines = responseText.split(/[\r\n&]+/);
  let pollUrl = '', success = false, error = '';
  
  for (const line of lines) {
    if (!line.includes('=')) continue;
    const equalIndex = line.indexOf('=');
    const key = line.substring(0, equalIndex).toLowerCase();
    const value = decodeURIComponent(line.substring(equalIndex + 1));
    
    if (key === 'pollurl') pollUrl = value;
    if (key === 'status') success = value.toLowerCase() === 'ok';
    if (key === 'error') error = value;
  }

  return res.status(200).json({ 
    success, 
    pollUrl, 
    error, 
    reference 
  });
}

async function handlePoll(req, res) {
  const pollUrl = req.query?.pollUrl || req.body?.pollUrl;
  
  if (!pollUrl) {
    return res.status(400).json({ 
      paid: false, 
      status: 'Error', 
      error: 'Poll URL is required' 
    });
  }

  console.log('Polling PayNow:', pollUrl);

  try {
    const response = await fetch(pollUrl, {
      method: 'POST',
      headers: {
        'User-Agent': 'AfriNova-Academy/1.0'
      },
      body: '',
    });

    const responseText = await response.text();
    console.log('Poll Response:', responseText);

    // Parse the URL-encoded response
    const dict = {};
    const pairs = responseText.split('&');
    
    for (const pair of pairs) {
      if (!pair.includes('=')) continue;
      const equalIndex = pair.indexOf('=');
      const key = pair.substring(0, equalIndex).toLowerCase();
      const value = decodeURIComponent(pair.substring(equalIndex + 1));
      dict[key] = value;
    }

    const status = dict['status'] || 'pending';
    
    return res.status(200).json({
      paid: status.toLowerCase() === 'paid',
      status: status.toLowerCase(),
      reference: dict['reference'] || '',
      amount: parseFloat(dict['amount']) || 0,
      paynowReference: dict['paynowreference'] || '',
    });

  } catch (error) {
    console.error('Poll error:', error);
    return res.status(200).json({
      paid: false,
      status: 'error',
      error: 'Failed to poll payment status'
    });
  }
}