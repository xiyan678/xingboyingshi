<?php
namespace app\api\controller;

use think\Controller;
use think\Db;
use think\Cache;

/** Additive mobile extension. Uses the site's User model for ALL password checks. */
class Xingbo extends Controller
{
    protected function runAction($fn)
    {
        try {
            if (!config('xingbo.enabled')) return json(['code'=>503,'msg'=>'APP 扩展尚未启用']);
            $GLOBALS['config'] = config('maccms');
            $result = $fn();
            return json(array_merge(['code'=>1,'msg'=>'ok'], $result));
        } catch (\InvalidArgumentException $e) {
            return json(['code'=>$e->getCode() ?: 400,'msg'=>$e->getMessage()]);
        } catch (\Exception $e) {
            // Keep database details in the private server log, never in API responses.
            if (strtolower($this->request->action()) === 'catalog') {
                error_log('[Xingbo catalog] '.get_class($e).': '.$e->getMessage().' at '.$e->getFile().':'.$e->getLine());
                \think\Log::record('[Xingbo catalog] '.get_class($e).': '.$e->getMessage().' at '.$e->getFile().':'.$e->getLine(), 'error');
            }
            return json(['code'=>503,'msg'=>'APP 服务暂不可用，请检查扩展配置和数据库迁移']);
        }
    }
    protected function postOnly()
    {
        if (!$this->request->isPost()) throw new \InvalidArgumentException('请使用 POST 请求',405);
        if (intval($this->request->server('CONTENT_LENGTH')) > 8192) throw new \InvalidArgumentException('请求过大',413);
    }
    protected function integer($key, $default, $min, $max)
    {
        $value = $this->request->param($key, $default);
        if (filter_var($value,FILTER_VALIDATE_INT) === false || $value < $min || $value > $max) throw new \InvalidArgumentException('参数错误：'.$key,400);
        return intval($value);
    }
    protected function rate($scope, $limit, $seconds)
    {
        // REMOTE_ADDR only: do not trust client-supplied X-Forwarded-For.
        $bucket=hash('sha256',$scope.'|'.$this->request->server('REMOTE_ADDR').'|'.floor(time()/$seconds));
        $prefix=config('database.prefix');
        if (!preg_match('/^[a-zA-Z0-9_]*$/',$prefix)) throw new \Exception('Invalid table prefix');
        Db::execute('INSERT INTO `'.$prefix.'xb_rate` (bucket,hits,expires_at) VALUES (?,1,?) ON DUPLICATE KEY UPDATE hits=hits+1',[$bucket,time()+$seconds]);
        if (Db::name('xb_rate')->where('bucket',$bucket)->value('hits') > $limit) throw new \InvalidArgumentException('操作过于频繁，请稍后再试',429);
        if (mt_rand(1,100)===1) {
            Db::name('xb_rate')->where('expires_at','<',time())->delete();
            Db::name('xb_sessions')->where('expires_at','<',time())->delete();
        }
    }
    protected function tokenHash()
    {
        $header=$this->request->header('authorization','');
        if (!preg_match('/^Bearer ([a-f0-9]{64})$/i',$header,$m)) throw new \InvalidArgumentException('请先登录',401);
        return hash('sha256',$m[1]);
    }
    protected function user()
    {
        $session=Db::name('xb_sessions')->where('token_hash',$this->tokenHash())->where('expires_at','>',time())->find();
        if (!$session) throw new \InvalidArgumentException('登录已过期，请重新登录',401);
        $user=Db::name('user')->where('user_id',$session['user_id'])->where('user_status',1)->find();
        if (!$user || !hash_equals($session['password_stamp'],hash('sha256',$user['user_pwd']))) throw new \InvalidArgumentException('登录已失效，请重新登录',401);
        return $user;
    }
    protected function publicUser($user)
    {
        return ['id'=>intval($user['user_id']),'name'=>$user['user_name'],'nickname'=>isset($user['user_nick_name'])?$user['user_nick_name']:''];
    }
    public function health()
    {
        return $this->runAction(function(){
            Db::name('xb_sessions')->limit(1)->select();
            Db::name('xb_rate')->limit(1)->select();
            Db::name('xb_progress')->limit(1)->select();
            Db::name('xb_danmaku')->limit(1)->select();
            $c=config('maccms.user');
            return ['version'=>1,'registration'=>!empty($c['status'])&&!empty($c['reg_open']), 'captcha_login'=>!empty($c['login_verify']), 'captcha_register'=>!empty($c['reg_verify']), 'extra_registration'=>!empty($c['reg_phone_sms'])||!empty($c['reg_email_sms']), 'danmaku'=>!!config('xingbo.danmaku_enabled')];
        });
    }
    public function captcha()
    {
        if (!config('xingbo.enabled')) return json(['code'=>503,'msg'=>'APP 扩展尚未启用']);
        return captcha();
    }
    public function register()
    {
        return $this->runAction(function(){
            $this->postOnly(); $this->rate('register',5,3600);
            $c=config('maccms.user');
            if (!empty($c['reg_phone_sms'])||!empty($c['reg_email_sms'])) throw new \InvalidArgumentException('网站要求短信或邮箱验证，请先在网站完成注册',400);
            $name=trim((string)$this->request->post('name',''));
            $pwd=(string)$this->request->post('password','');
            if (!preg_match('/^[a-zA-Z0-9]{3,20}$/',$name)||strlen($pwd)<8||strlen($pwd)>64) throw new \InvalidArgumentException('用户名需为3–20位字母数字，密码需为8–64位',400);
            $result=model('User')->register(['user_name'=>$name,'user_pwd'=>$pwd,'user_pwd2'=>$pwd,'verify'=>(string)$this->request->post('captcha','')]);
            if (intval($result['code'])!==1) throw new \InvalidArgumentException((string)$result['msg'],400);
            return ['msg'=>'注册成功，可使用同一账号登录网站。若网站开启审核，请等待审核后登录。'];
        });
    }
    public function login()
    {
        return $this->runAction(function(){
            $this->postOnly(); $this->rate('login',20,600);
            $userConfig=config('maccms.user');
            if (empty($userConfig['status'])) throw new \InvalidArgumentException('网站用户系统未开启',403);
            $name=trim((string)$this->request->post('name',''));
            $pwd=(string)$this->request->post('password','');
            if (strlen($name)>100||strlen($pwd)>128||$name===''||$pwd==='') throw new \InvalidArgumentException('请输入账号和密码',400);
            $result=model('User')->login(['user_name'=>$name,'user_pwd'=>$pwd,'verify'=>(string)$this->request->post('captcha',''),'openid'=>'','col'=>'']);
            if (intval($result['code'])!==1) throw new \InvalidArgumentException('登录失败：'.(string)$result['msg'],401);
            // The CMS model validated the credentials. Retrieve only that exact identity.
            $field=strpos($name,'@')!==false?'user_email':'user_name';
            $user=Db::name('user')->where($field,$name)->where('user_status',1)->find();
            if (!$user) throw new \InvalidArgumentException('账号状态异常',401);
            $token=bin2hex(random_bytes(32));
            $days=max(1,min(90,intval(config('xingbo.token_days'))));
            Db::name('xb_sessions')->insert(['token_hash'=>hash('sha256',$token),'user_id'=>$user['user_id'],'password_stamp'=>hash('sha256',$user['user_pwd']),'expires_at'=>time()+$days*86400]);
            return ['token'=>$token,'user'=>$this->publicUser($user)];
        });
    }
    public function me() { return $this->runAction(function(){return ['user'=>$this->publicUser($this->user())];}); }
    public function logout() { return $this->runAction(function(){$this->postOnly();Db::name('xb_sessions')->where('token_hash',$this->tokenHash())->delete();return [];}); }
    protected function film($id)
    {
        $film=Db::name('vod')->where('vod_id',$id)->where('vod_status',1)->find();
        if (!$film) throw new \InvalidArgumentException('影片不存在或已下架',404);
        return $film;
    }
    protected function publicFilm($film)
    {
        $out=array_intersect_key($film,array_flip(['vod_id','vod_name','type_id','vod_pic','vod_remarks','vod_year','vod_area','vod_lang','vod_class','vod_content','vod_blurb','vod_actor','vod_director','vod_score','vod_hits','vod_time','vod_play_from','vod_play_url']));
        // The extension does not implement VIP/payment/password-gated playback.
        if (!empty($film['vod_pwd'])||!empty($film['vod_pwd_play'])||!empty($film['vod_points_play'])) { $out['vod_play_url']='';$out['vod_play_from']=''; }
        return $out;
    }
    protected function episode($film)
    {
        $episode=$this->integer('episode',1,1,10000);
        $max=0;
        foreach(explode('$$$',$film['vod_play_url']) as $line) $max=max($max,count(explode('#',$line)));
        if ($episode>$max) throw new \InvalidArgumentException('集数不存在',400);
        return $episode;
    }
    public function catalog()
    {
        return $this->runAction(function(){
            $page=$this->integer('pg',1,1,100000);
            $type=$this->integer('t',0,0,100000);
            $conditions=[['vod_status','=',1]];
            if ($type) {
                $ids=Db::name('type')->where('type_pid',$type)->column('type_id'); $ids[]=$type;
                $conditions[]=['type_id','in',$ids];
            }
            $keyword=trim((string)$this->request->param('wd',''));
            if (mb_strlen($keyword)>80) throw new \InvalidArgumentException('关键词过长',400);
            if ($keyword!=='') $conditions[]=['vod_name','like','%'.addcslashes($keyword,'%_\\').'%'];
            foreach(['class'=>'vod_class','year'=>'vod_year','area'=>'vod_area','lang'=>'vod_lang','letter'=>'vod_letter'] as $key=>$column) {
                $value=trim((string)$this->request->param($key,''));
                if (mb_strlen($value)>40) throw new \InvalidArgumentException('筛选参数过长',400);
                if ($value!=='') {
                    if (in_array($key,['class','area','lang'],true)) {
                        $conditions[]=[$column,'like','%'.addcslashes($value,'%_\\').'%'];
                    } elseif ($key==='letter' && $value==='0-9') {
                        $conditions[]=[$column,'in',['0','1','2','3','4','5','6','7','8','9']];
                    } else { $conditions[]=[$column,'=',$value]; }
                }
            }
            $sorts=['time'=>'vod_time','hits'=>'vod_hits','score'=>'vod_score'];
            $sort=(string)$this->request->param('sort','time');
            if (!isset($sorts[$sort])) throw new \InvalidArgumentException('排序参数错误',400);
            // Do not clone ThinkPHP 5.0 Query: its builder may still bind to
            // the original query, leaving the clone without PDO parameters.
            $makeQuery=function() use ($conditions) {
                $query=Db::name('vod');
                foreach ($conditions as $condition) {
                    $query->where($condition[0],$condition[1],$condition[2]);
                }
                return $query;
            };
            $count=$makeQuery()->count();
            $list=$makeQuery()->order($sorts[$sort].' desc,vod_id desc')->page($page,24)->select();
            return ['list'=>array_map([$this,'publicFilm'],$list),'pagecount'=>max(1,intval(ceil($count/24))),'total'=>$count];
        });
    }
    public function filters()
    {
        return $this->runAction(function(){
            $out=[];
            foreach(['year'=>'vod_year','area'=>'vod_area','lang'=>'vod_lang'] as $key=>$field) {
                $out[$key]=Db::name('vod')->where('vod_status',1)->where($field,'<>','')->distinct(true)->order($field.' desc')->limit(300)->column($field);
            }
            return ['filters'=>$out];
        });
    }
    public function progress()
    {
        return $this->runAction(function(){
            $user=$this->user();
            if ($this->request->isGet()) {
                $rows=Db::name('xb_progress')->where('user_id',$user['user_id'])->order('updated_at desc')->limit(100)->select();
                $list=[];
                foreach($rows as $row){
                    $film=Db::name('vod')->where('vod_id',$row['vod_id'])->where('vod_status',1)->find();
                    if($film){$row['film']=$this->publicFilm($film);unset($row['user_id']);$list[]=$row;}
                }
                return ['list'=>$list];
            }
            $this->postOnly(); $this->rate('progress-'.$user['user_id'],180,600);
            $film=$this->film($this->integer('vod_id',0,1,2147483647));
            $episode=$this->episode($film);
            $position=$this->integer('position_ms',0,0,86400000);
            $line=(string)$this->request->post('line_name','');
            if (!in_array($line,explode('$$$',$film['vod_play_from']),true)) throw new \InvalidArgumentException('播放线路不存在',400);
            $where=['user_id'=>$user['user_id'],'vod_id'=>$film['vod_id']];
            // One atomic upsert, bound values. Latest received playback event wins.
            $prefix=config('database.prefix');
            if (!preg_match('/^[a-zA-Z0-9_]*$/',$prefix)) throw new \Exception('Invalid prefix');
            Db::execute('INSERT INTO `'.$prefix.'xb_progress` (user_id,vod_id,episode,line_name,position_ms,updated_at) VALUES (?,?,?,?,?,?) ON DUPLICATE KEY UPDATE episode=VALUES(episode),line_name=VALUES(line_name),position_ms=VALUES(position_ms),updated_at=VALUES(updated_at)',[$where['user_id'],$where['vod_id'],$episode,$line,$position,time()]);
            return [];
        });
    }
    public function clear_progress()
    {
        return $this->runAction(function(){$this->postOnly();$u=$this->user();Db::name('xb_progress')->where('user_id',$u['user_id'])->delete();return [];});
    }
    public function danmaku()
    {
        return $this->runAction(function(){
            if (!config('xingbo.danmaku_enabled')) throw new \InvalidArgumentException('弹幕暂未开启',403);
            $film=$this->film($this->integer('vod_id',0,1,2147483647)); $episode=$this->episode($film);
            if ($this->request->isGet()) {
                $from=$this->integer('from_ms',0,0,86400000);$to=min(86400000,$from+60000);
                $rows=Db::name('xb_danmaku')->field('id,position_ms,content')->where(['vod_id'=>$film['vod_id'],'episode'=>$episode,'status'=>1])->where('position_ms','between',[$from,$to])->order('position_ms asc,id asc')->limit(300)->select();
                if (config('xingbo.external_danmaku_enabled')) {
                    foreach ($this->externalDanmaku($film,$episode) as $row) {
                        if ($row['position_ms'] >= $from && $row['position_ms'] <= $to) $rows[]=$row;
                    }
                    usort($rows,function($a,$b){return intval($a['position_ms'])<=>intval($b['position_ms']);});
                    $rows=array_slice($rows,0,500);
                }
                return ['list'=>$rows];
            }
            $this->postOnly();$u=$this->user();$this->rate('danmaku-'.$u['user_id'],1,10);
            $content=trim((string)$this->request->post('content',''));
            if ($content===''||mb_strlen($content)>80||preg_match('/[\x00-\x1F\x7F<>]/u',$content)) throw new \InvalidArgumentException('弹幕需为1–80个字，不能包含换行或标签',400);
            $position=$this->integer('position_ms',0,0,86400000);
            $review=!!config('xingbo.danmaku_review');
            $id=Db::name('xb_danmaku')->insertGetId(['user_id'=>$u['user_id'],'vod_id'=>$film['vod_id'],'episode'=>$episode,'position_ms'=>$position,'content'=>$content,'status'=>$review?0:1,'created_at'=>time()]);
            return ['id'=>$id,'pending'=>$review,'msg'=>$review?'弹幕已提交，审核通过后显示':'弹幕发送成功'];
        });
    }

    protected function externalJson($url)
    {
        $appId=trim((string)config('xingbo.external_danmaku_app_id'));
        $appSecret=trim((string)config('xingbo.external_danmaku_app_secret'));
        if ($appId==='' || $appSecret==='') return null;
        if (preg_match('/[\r\n]/',$appId.$appSecret)) return null;
        $context=stream_context_create(['http'=>[
            'method'=>'GET','timeout'=>6,'ignore_errors'=>true,
            'header'=>"Accept: application/json\r\n".
                "User-Agent: XingboCinema/1.0\r\n".
                "X-AppId: ".$appId."\r\n".
                "X-AppSecret: ".$appSecret."\r\n"
        ]]);
        $raw=@file_get_contents($url,false,$context);
        if ($raw===false || strlen($raw)>8388608) return null;
        $data=json_decode($raw,true);
        return is_array($data)?$data:null;
    }

    protected function externalDanmaku($film,$episode)
    {
        $base=rtrim((string)config('xingbo.external_danmaku_api'),'/');
        if ($base==='' || !preg_match('#^https://#i',$base)) return [];
        $cacheKey='xingbo_ext_dm_'.intval($film['vod_id']).'_'.intval($episode);
        $cached=Cache::get($cacheKey);
        if (is_array($cached)) return $cached;
        $episodeId=0;
        $title=trim((string)$film['vod_name']);
        $queries=[$title];
        $withoutYear=trim(preg_replace('/(?:19|20)\d{2}$/u','',$title));
        $baseTitle=trim(preg_replace('/(?:第[一二三四五六七八九十百0-9]+季|[\s·:_：-]*年番)$/u','',$withoutYear));
        if ($withoutYear!=='' && $withoutYear!==$title) $queries[]=$withoutYear;
        if ($baseTitle!=='' && !in_array($baseTitle,$queries,true)) $queries[]=$baseTitle;
        foreach ($queries as $query) {
            $search=$this->externalJson($base.'/search/episodes?anime='.rawurlencode($query).'&episode='.intval($episode).'&v2=true');
            if (!$search || empty($search['animes']) || !is_array($search['animes'])) continue;
            foreach ($search['animes'] as $anime) {
                if (empty($anime['episodes']) || !is_array($anime['episodes'])) continue;
                foreach ($anime['episodes'] as $candidate) {
                    if (!empty($candidate['episodeId'])) {$episodeId=intval($candidate['episodeId']);break 3;}
                }
            }
        }
        if ($episodeId<1) return [];
        $payload=$this->externalJson($base.'/comment/'.$episodeId.'?withRelated=true&chConvert=1');
        if (!$payload || empty($payload['comments']) || !is_array($payload['comments'])) return [];
        $rows=[];
        foreach (array_slice($payload['comments'],0,5000) as $comment) {
            $parts=explode(',',isset($comment['p'])?(string)$comment['p']:'');
            $content=trim(isset($comment['m'])?(string)$comment['m']:'');
            if (count($parts)<1 || $content==='' || mb_strlen($content)>100) continue;
            $position=max(0,min(86400000,intval(round(floatval($parts[0])*1000))));
            $seed=isset($comment['cid'])?(string)$comment['cid']:$episodeId.'|'.$position.'|'.$content;
            $rows[]=['id'=>1000000000+(intval(sprintf('%u',crc32($seed)))%1000000000),'position_ms'=>$position,'content'=>$content,'source'=>'external'];
        }
        Cache::set($cacheKey,$rows,21600);
        return $rows;
    }

    // Public app feed for enabled advertisements. Management should be done
    // from the CMS admin side; this endpoint only exposes active campaigns.
    public function ads()
    {
        return $this->runAction(function(){
            $slot=trim((string)$this->request->param('slot',''));
            if ($slot!=='' && !preg_match('/^[a-z0-9_]{1,40}$/',$slot)) throw new \InvalidArgumentException('广告位错误',400);
            $now=time(); $q=Db::name('xb_ads')->where('enabled',1)
                ->where(function($w) use ($now){$w->whereNull('starts_at')->whereOr('starts_at','<=',$now);})
                ->where(function($w) use ($now){$w->whereNull('ends_at')->whereOr('ends_at','>=',$now);});
            if ($slot!=='') $q->where('slot',$slot);
            $rows=$q->field('id,slot,title,image_url,target_url,sort_order')->order('sort_order asc,id desc')->limit(20)->select();
            return ['list'=>$rows];
        });
    }
    public function play_event()
    {
        return $this->runAction(function(){
            $this->postOnly(); $this->rate('play-event',60,600);
            $this->film($this->integer('vod_id',0,1,2147483647));
            $prefix=config('database.prefix');
            if (!preg_match('/^[a-zA-Z0-9_]*$/',$prefix)) throw new \Exception('Invalid prefix');
            Db::execute('INSERT INTO `'.$prefix.'xb_stats_daily` (stat_date,plays,updated_at) VALUES (?,1,?) ON DUPLICATE KEY UPDATE plays=plays+1,updated_at=VALUES(updated_at)',[date('Y-m-d'),time()]);
            return [];
        });
    }
    public function ad_impression()
    {
        return $this->runAction(function(){
            $this->postOnly(); $this->rate('ad-impression',120,600); $id=$this->integer('id',0,1,2147483647);
            Db::name('xb_ads')->where('id',$id)->where('enabled',1)->setInc('impressions');
            return [];
        });
    }
    public function ad_click()
    {
        return $this->runAction(function(){
            $this->postOnly(); $this->rate('ad-click',60,600); $id=$this->integer('id',0,1,2147483647);
            Db::name('xb_ads')->where('id',$id)->where('enabled',1)->setInc('clicks');
            return [];
        });
    }
}
