<?php if (!defined('THINK_VERSION')) { http_response_code(403); exit; } ?>
<!doctype html><html lang="zh"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>星播运营管理</title>
<style>body{margin:0;background:#f3f5f9;color:#233047;font:15px system-ui}main{max-width:1200px;margin:auto;padding:24px}h1{font-size:26px}.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:12px}.card,section{background:white;padding:20px;border-radius:12px;margin-bottom:16px}.card strong{display:block;font-size:28px;margin-top:10px}form{display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:16px}label{display:grid;gap:8px}input,select,button{font:inherit;padding:12px;border:1px solid #ccd3df;border-radius:6px;min-width:0}button{background:#246bfd;color:white;cursor:pointer}table{border-collapse:collapse;width:100%}td,th{text-align:left;padding:12px;border-bottom:1px solid #eee}.scroll{overflow:auto}a{color:#246bfd}.note{color:#58667a;line-height:1.7}</style>
<main><h1>星播 · 统计与广告管理</h1><p class="note">统计取自本站数据库。时间使用服务器时区。播放启动按每次打开影片后首次播放计数；广告展示按图片加载成功计数，点击按打开链接计数。均为客户端上报，未去重，不等同于独立用户或广告结算数据。0.2.6以前的APP不支持广告展示。</p>
<div class="cards"><?php foreach($stats as $label=>$value): ?><div class="card"><?= $e($label) ?><strong><?= $e($value ?: 0) ?></strong></div><?php endforeach ?></div>
<section><h2><?= empty($edit)?'新增广告':'编辑广告 #'.$e($edit['id']) ?></h2><p class="note">图片可先通过宝塔上传到网站，再填写图片的完整网址。留空时间表示不限制；停用请编辑并选择“停用”。</p>
<form method="post" action="<?= $e(url('xbmanage/index')) ?>">
<input type="hidden" name="csrf" value="<?= $e($token) ?>"><input type="hidden" name="id" value="<?= $e($edit['id'] ?? 0) ?>">
<label>标题<input name="title" required maxlength="120" value="<?= $e($edit['title'] ?? '') ?>"></label>
<label>广告位<select name="slot"><?php foreach($slots as $key=>$label): ?><option value="<?= $e($key) ?>" <?= ($edit['slot'] ?? '')===$key?'selected':'' ?>><?= $e($label) ?></option><?php endforeach ?></select></label>
<label>图片网址<input name="image_url" type="url" required maxlength="1024" value="<?= $e($edit['image_url'] ?? '') ?>"></label>
<label>跳转网址<input name="target_url" type="url" required maxlength="1024" value="<?= $e($edit['target_url'] ?? '') ?>"></label>
<label>状态<select name="enabled"><option value="1">启用</option><option value="0" <?= isset($edit['enabled']) && !$edit['enabled']?'selected':'' ?>>停用</option></select></label>
<label>排序（小值优先）<input name="sort_order" type="number" value="<?= $e($edit['sort_order'] ?? 0) ?>"></label>
<?php foreach(['starts_at'=>'开始时间','ends_at'=>'结束时间'] as $key=>$label): ?><label><?= $e($label) ?><input type="datetime-local" name="<?= $e($key) ?>" value="<?= empty($edit[$key])?'':$e(date('Y-m-d\TH:i',$edit[$key])) ?>"></label><?php endforeach ?>
<button type="submit">保存广告</button><a href="<?= $e(url('xbmanage/index')) ?>">取消编辑 / 刷新统计</a></form></section>
<section><h2>广告列表</h2><div class="scroll"><table><tr><th>标题</th><th>广告位</th><th>状态</th><th>排序</th><th>展示</th><th>点击</th><th>操作</th></tr>
<?php foreach($ads as $ad): ?><tr><td><?= $e($ad['title']) ?></td><td><?= $e($slots[$ad['slot']] ?? $ad['slot']) ?></td><td><?= $ad['enabled']?'启用':'停用' ?></td><td><?= $e($ad['sort_order']) ?></td><td><?= $e($ad['impressions']) ?></td><td><?= $e($ad['clicks']) ?></td><td><a href="<?= $e(url('xbmanage/index',['edit'=>$ad['id']])) ?>">编辑</a></td></tr><?php endforeach ?>
</table></div><?php if (!$ads): ?><p>暂无广告，请在上方添加。</p><?php endif ?></section></main></html>
