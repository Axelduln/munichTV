<?php
$info  = $_REQUEST['info']  ?? '';
$cb    = $_REQUEST['cb']    ?? '';
$token = $_REQUEST['token'] ?? '';

if (!$cb && $token) {
  $file = __DIR__ . '/tmp/' . preg_replace('/[^a-f0-9]/', '', $token);
  $cb   = file_exists($file) ? trim(file_get_contents($file)) : '';
}

if (!$cb) {
  die("ERROR: missing callback");
}

$opts = array(
  'http' => array(
    'method'  => 'PUT',
    'header'  => "Content-type: application/x-www-form-urlencoded\r\n",
    'content' => 'value=' . urlencode($info)
  ),
  'ssl' => array(
    'verify_peer'      => false,
    'verify_peer_name' => false,
  )
);
$context = stream_context_create($opts);
$res = file_get_contents($cb, false, $context);
$ok  = ($res !== false);

$labels = [
  'blockbuster' => 'Blockbuster',
  'mixed'       => 'Mixed',
  'arthouse'    => 'Arthouse',
];
$label = $labels[$info] ?? $info;
?>
<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>München Kinos</title>
  <style>
    body { margin:0; display:flex; align-items:center; justify-content:center;
           min-height:100vh; background:#0a0a0a; color:#e5e5e5;
           font-family:system-ui,sans-serif; text-align:center; padding:24px; box-sizing:border-box; }
    .card { background:#111; border:1px solid #2a2a2a; padding:40px 32px; max-width:360px; width:100%; }
    h1 { font-size:1.4rem; margin:12px 0 8px; }
    p  { color:#a3a3a3; font-size:0.9rem; margin:0; }
  </style>
</head>
<body>
  <div class="card">
    <?php if ($ok): ?>
      <h1><?= htmlspecialchars($label) ?></h1>
      <p>Du kannst diese Seite schließen.</p>
    <?php else: ?>
      <h1>Verbindung fehlgeschlagen</h1>
      <p>Bitte am Kiosk erneut versuchen.</p>
    <?php endif; ?>
  </div>
</body>
</html>
