export default async function handler(req, res) {
  // Enable CORS for all origins
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  // Handle preflight OPTIONS request
  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  // Only allow POST requests
  if (req.method !== 'POST') {
    return res.status(405).json({ 
      success: false, 
      error: 'Method not allowed' 
    });
  }

  try {
    const { reference, amount, mobileNumber, email } = req.body;
    
    // Validate required fields
    if (!reference || !amount || !mobileNumber) {
      return res.status(400).json({ 
        success: false, 
        error: 'Missing required fields: reference, amount, mobileNumber' 
      });
    }

    const amountStr = Number(amount).toFixed(2);
    const autoEmail = email?.trim() || `${mobileNumber}@mobile.paynow.co.zw`;

    // Get credentials from Vercel environment variables
    const integrationId = process.env.PAYNOW_INTEGRATION_ID;
    const integrationKey = process.env.PAYNOW_INTEGRATION_KEY;

    if (!integrationId || !integrationKey) {
      console.error('PayNow credentials not configured');
      return res.status(500).json({ 
        success: false, 
        error: 'Payment gateway not configured' 
      });
    }

    // Build hash string (PayNow uses SHA512)
    const crypto = require('crypto');
    const hashInput = 
      integrationId + 
      reference + 
      amountStr + 
      '' + // additionalinfo is empty
      'https://afrinova.academy/payment/complete' + // returnurl
      'https://rwheufzhixqqifoleltu.supabase.co/functions/v1/paynow-webhook' + // resulturl
      'Message' + // status
      mobileNumber.trim() + 
      'ecocash' + // method
      integrationKey;
    
    const hash = crypto.createHash('sha512').update(hashInput).digest('hex').toUpperCase();

    // Build form data exactly as PayNow expects
    const formData = new URLSearchParams({
      id: integrationId,
      reference: reference,
      amount: amountStr,
      authemail: autoEmail,
      additionalinfo: '',
      returnurl: 'https://afrinova.academy/payment/complete',
      resulturl: 'https://rwheufzhixqqifoleltu.supabase.co/functions/v1/paynow-webhook',
      status: 'Message',
      phone: mobileNumber.trim(),
      method: 'ecocash',
      hash: hash,
    });

    console.log('Sending to PayNow:', formData.toString());

    // Send to PayNow
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
    
    // Parse PayNow response (URL-encoded format)
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

    if (!success) {
      console.error('PayNow error:', error || 'Unknown error');
    }

    return res.status(200).json({ 
      success, 
      pollUrl, 
      error, 
      reference 
    });

  } catch (error) {
    console.error('Server Error:', error);
    return res.status(500).json({ 
      success: false, 
      error: 'Payment service temporarily unavailable' 
    });
  }
}