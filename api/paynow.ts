export default async function handler(req, res) {
  // Enable CORS
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ success: false, error: 'Method not allowed' });
  }

  try {
    const { reference, amount, mobileNumber, email } = req.body;
    const amountStr = Number(amount).toFixed(2);
    const autoEmail = email?.trim() || `${mobileNumber}@mobile.paynow.co.zw`;

    // Get credentials from Vercel environment variables
    const integrationId = process.env.PAYNOW_INTEGRATION_ID;
    const integrationKey = process.env.PAYNOW_INTEGRATION_KEY;

    if (!integrationId || !integrationKey) {
      return res.status(500).json({ success: false, error: 'Payment gateway not configured' });
    }

    // Build hash string (PayNow uses SHA512)
    const crypto = require('crypto');
    const hashInput = integrationId + reference + amountStr + '' + 
      'https://afrinova-academy.com/payment/complete' +
      'https://rwheufzhixqqifoleltu.supabase.co/functions/v1/paynow-webhook' +
      'Message' + mobileNumber.trim() + 'ecocash' + integrationKey;
    
    const hash = crypto.createHash('sha512').update(hashInput).digest('hex').toUpperCase();

    // Build form data
    const formData = new URLSearchParams({
      id: integrationId,
      reference: reference,
      amount: amountStr,
      authemail: autoEmail,
      additionalinfo: '',
      returnurl: 'https://afrinova-academy.com/payment/complete',
      resulturl: 'https://rwheufzhixqqifoleltu.supabase.co/functions/v1/paynow-webhook',
      status: 'Message',
      phone: mobileNumber.trim(),
      method: 'ecocash',
      hash: hash,
    });

    // Send to PayNow
    const paynowResponse = await fetch('https://www.paynow.co.zw/interface/remotetransaction', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: formData.toString(),
    });

    const responseText = await paynowResponse.text();
    
    // Parse PayNow response
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

    return res.status(200).json({ success, pollUrl, error, reference });

  } catch (error) {
    console.error('PayNow Error:', error);
    return res.status(500).json({ success: false, error: 'Payment service temporarily unavailable' });
  }
}