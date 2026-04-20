<?php
$cb = $_REQUEST['cb'] ?? '';
if (!$cb) { http_response_code(400); die('missing cb'); }

$token = bin2hex(random_bytes(3)); // 6-char hex token
$dir   = __DIR__ . '/tmp';
if (!is_dir($dir)) mkdir($dir, 0777, true);
file_put_contents($dir . '/' . $token, $cb);
echo $token;
