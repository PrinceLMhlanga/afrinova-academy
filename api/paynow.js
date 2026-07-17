export default async function handler(req, res) {
  // CORS headers
  const origin = req.headers.origin || '*';
  res.setHeader('Access-Control-Allow-Origin', origin);
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.setHeader('Access-Control-Max-Age', '86400');

  // Handle preflight OPTIONS request
  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ 
      success: false, 
      error: 'Method not allowed' 
    });
  }

  try {
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

    // Build object with ALL fields in correct order
    const fieldsToHash = {
      id: integrationId,
      reference: reference,
      amount: amountStr,
      additionalinfo: '',
      returnurl: 'https://afrinova-academy.com/payment/complete',
      resulturl: 'https://rwheufzhixqqifoleltu.supabase.co/functions/v1/paynow-webhook',
      authemail: autoEmail,
      phone: mobileNumber.trim(),
      method: 'ecocash',
      status: 'Message'
    };

    // Concatenate all values in strict sequence
    const concatString = 
      fieldsToHash.id +
      fieldsToHash.reference +
      fieldsToHash.amount +
      fieldsToHash.additionalinfo +
      fieldsToHash.returnurl +
      fieldsToHash.resulturl +
      fieldsToHash.authemail +
      fieldsToHash.phone +
      fieldsToHash.method +
      fieldsToHash.status;

    // Append integration key
    const stringToHash = concatString + integrationKey;
    
    console.log('Hash input:', stringToHash);

    // Generate SHA512 hash (uppercase)
    const crypto = require('crypto');
    const hash = crypto.createHash('sha512').update(stringToHash).digest('hex').toUpperCase();
    
    console.log('Generated hash:', hash);

    // Build form data using EXACT same values
    const formData = new URLSearchParams();
    formData.append('id', fieldsToHash.id);
    formData.append('reference', fieldsToHash.reference);
    formData.append('amount', fieldsToHash.amount);
    formData.append('additionalinfo', fieldsToHash.additionalinfo);
    formData.append('returnurl', fieldsToHash.returnurl);
    formData.append('resulturl', fieldsToHash.resulturl);
    formData.append('authemail', fieldsToHash.authemail);
    formData.append('phone', fieldsToHash.phone);
    formData.append('method', fieldsToHash.method);
    formData.append('status', fieldsToHash.status);
    formData.append('hash', hash);

    console.log('Sending to PayNow...');

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

  } catch (error) {
    console.error('Server Error:', error);
    return res.status(500).json({ 
      success: false, 
      error: 'Payment service temporarily unavailable' 
    });
  }
}