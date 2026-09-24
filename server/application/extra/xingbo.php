<?php
return [
    // Run install.sql with the correct prefix before enabling the extension.
    'enabled' => false,
    'danmaku_enabled' => true,
    'danmaku_review' => true,
    'external_danmaku_enabled' => true,
    'external_danmaku_api' => 'https://api.dandanplay.net/api/v2',
    'external_danmaku_app_id' => '',
    'external_danmaku_app_secret' => '',
    'token_days' => 30,
];
