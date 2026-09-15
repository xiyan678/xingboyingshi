<?php
namespace app\admin\controller;
use think\Db;

/** Uses the existing CMS login and permission checks. */
class Xbmanage extends Base
{
    public function index()
    {
        if (empty($this->_admin) || (string)$this->_admin['admin_id'] !== '1') {
            return $this->error('请使用主管理员账号登录');
        }
        if (!session('xb_manage_csrf')) session('xb_manage_csrf',bin2hex(random_bytes(32)));
        $token=session('xb_manage_csrf');
        $slots=['home_top'=>'首页轮播','home_banner'=>'首页横幅','detail'=>'详情页','player_bottom'=>'播放页底部'];
        $message='';
        try {
            if ($this->request->isPost()) {
                if (!hash_equals($token,(string)$this->request->post('csrf',''))) throw new \InvalidArgumentException('页面已过期，请刷新');
                $id=max(0,(int)$this->request->post('id',0));
                $slot=(string)$this->request->post('slot','');
                if (!isset($slots[$slot])) throw new \InvalidArgumentException('请选择广告位');
                $title=trim((string)$this->request->post('title',''));
                if ($title==='' || mb_strlen($title)>120) throw new \InvalidArgumentException('标题需为1–120字');
                $image=trim((string)$this->request->post('image_url',''));
                $target=trim((string)$this->request->post('target_url',''));
                foreach ([$image,$target] as $url) {
                    if (strlen($url)>1024 || !filter_var($url,FILTER_VALIDATE_URL) || !in_array(strtolower(parse_url($url,PHP_URL_SCHEME)),['http','https'],true)) throw new \InvalidArgumentException('图片和跳转地址必须为完整的 http/https 链接');
                }
                $start=$this->dateValue('starts_at'); $end=$this->dateValue('ends_at');
                if ($start && $end && $end<=$start) throw new \InvalidArgumentException('结束时间必须晚于开始时间');
                $data=['slot'=>$slot,'title'=>$title,'image_url'=>$image,'target_url'=>$target,'enabled'=>$this->request->post('enabled')==='1'?1:0,'sort_order'=>(int)$this->request->post('sort_order',0),'starts_at'=>$start,'ends_at'=>$end,'updated_at'=>time()];
                if ($id) {
                    if (!Db::name('xb_ads')->where('id',$id)->find()) throw new \InvalidArgumentException('广告不存在');
                    Db::name('xb_ads')->where('id',$id)->update($data);
                } else { $data['created_at']=time(); Db::name('xb_ads')->insert($data); }
                return $this->redirect('xbmanage/index');
            }
            $ads=Db::name('xb_ads')->order('sort_order asc,id desc')->limit(500)->select();
            $stats=[
                'APP累计播放启动'=>Db::name('xb_stats_daily')->sum('plays'),
                'APP今日播放启动'=>Db::name('xb_stats_daily')->where('stat_date',date('Y-m-d'))->sum('plays'),
                '影片总数'=>Db::name('vod')->count(),
                '注册用户'=>Db::name('user')->count(),
                '今日注册'=>Db::name('user')->where('user_reg_time','>=',strtotime('today'))->count(),
                '网站累计点击（非APP播放）'=>Db::name('vod')->sum('vod_hits'),
                '弹幕总数'=>Db::name('xb_danmaku')->count(),
                '待审弹幕'=>Db::name('xb_danmaku')->where('status',0)->count(),
                '广告上报展示'=>Db::name('xb_ads')->sum('impressions'),
                '广告上报点击'=>Db::name('xb_ads')->sum('clicks')
            ];
            $edit=Db::name('xb_ads')->where('id',max(0,(int)$this->request->get('edit',0)))->find() ?: [];
        } catch (\InvalidArgumentException $e) { return $this->error($e->getMessage());
        } catch (\Exception $e) { return $this->error('读取失败，请确认已导入广告表，并保留原有弹幕表'); }
        $e=function($s){return htmlspecialchars((string)$s,ENT_QUOTES,'UTF-8');};
        ob_start();
        include __DIR__.'/../view/xbmanage/dashboard.php';
        return response(ob_get_clean());
    }
    protected function dateValue($key)
    {
        $value=trim((string)$this->request->post($key,''));
        if ($value==='') return null;
        $time=strtotime($value);
        if ($time===false) throw new \InvalidArgumentException('时间格式不正确');
        return $time;
    }
}
