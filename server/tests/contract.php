<?php
// Isolated contract tests: no website credentials, no real database writes.
namespace think {
    class Controller { public $request; public function __construct($r){$this->request=$r;} }
    class Db { public static $inserts=[]; public static function name($n){return new Query($n);} public static function execute($s,$p){return 1;} }
    class Query {
        private $name;
        public function __construct($n){$this->name=$n;}
        public function __call($n,$a){return $this;}
        public function value($f){return 1;}
        public function delete(){return 1;}
        public function select(){return [];}
        public function column($f){return [];}
        public function count(){return 0;}
        public function insert($v){Db::$inserts[]=$v;return 1;}
        public function find(){return $this->name==='user'?['user_id'=>7,'user_name'=>'alice','user_pwd'=>'cms-hash','user_status'=>1]:null;}
    }
}
namespace {
    $cfg=['xingbo.enabled'=>true,'xingbo.token_days'=>30,'database.prefix'=>'mac_','maccms'=>[],'maccms.user'=>['status'=>1],'maccms.user.status'=>null];
    function config($k){return isset($GLOBALS['cfg'][$k])?$GLOBALS['cfg'][$k]:null;}
    function json($v){return $v;}
    class UserModel {
        public $args=[],$code=1;
        public function register($v){$this->args=$v;return ['code'=>$this->code,'msg'=>'CMS result'];}
        public function login($v){$this->args=$v;return ['code'=>$this->code,'msg'=>'CMS result'];}
    }
    $model=new UserModel();
    function model($n){return $GLOBALS['model'];}
    class Request {
        public $data=[],$method='POST',$auth='';
        public function isPost(){return $this->method==='POST';}
        public function isGet(){return $this->method==='GET';}
        public function param($k,$d=null){return isset($this->data[$k])?$this->data[$k]:$d;}
        public function post($k,$d=null){return $this->param($k,$d);}
        public function server($k){return $k==='REMOTE_ADDR'?'127.0.0.1':0;}
        public function header($k,$d=''){return $this->auth;}
    }
    require __DIR__.'/../application/api/controller/Xingbo.php';
    $r=new Request();$api=new \app\api\controller\Xingbo($r);$checks=0;
    function check($ok,$name){if(!$ok)throw new \Exception('FAIL: '.$name);$GLOBALS['checks']++;echo 'PASS: '.$name.PHP_EOL;}
    $r->data=['name'=>'alice','password'=>'password123','captcha'=>'abcd','group_id'=>9,'user_points'=>99999];
    check($api->register()['code']===1,'registration delegates to CMS');
    check(array_keys($model->args)===['user_name','user_pwd','user_pwd2','verify'],'registration strips privilege fields');
    $model->code=0;check($api->register()['code']===400,'CMS registration denial respected');
    check($api->login()['code']===401 && count(\think\Db::$inserts)===0,'invalid credentials create no session');
    $model->code=1;$result=$api->login();
    check($result['code']===1 && strlen($result['token'])===64,'valid CMS login issues random session');
    check(\think\Db::$inserts[0]['token_hash']===hash('sha256',$result['token']),'only session hash persisted server side');
    check(!isset($result['user']['user_pwd']),'password hash not returned');
    check($model->args['openid']==='' && $model->args['col']==='','external identity login is not accepted');
    check($api->me()['code']===401,'missing bearer denied');
    $r->auth='Bearer invalid';check($api->me()['code']===401,'malformed bearer denied');
    $r->method='GET';check($api->register()['code']===405,'GET cannot register');
    $r->data=['sort'=>'vod_pwd desc'];check($api->catalog()['code']===400,'sort injection rejected');
    $cfg['xingbo.enabled']=false;check($api->health()['code']===503,'disabled extension fails closed');
    echo $checks.' contract checks passed; real CMS/database integration remains to be tested.'.PHP_EOL;
}
