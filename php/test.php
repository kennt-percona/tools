<?php
$dbhost = $argv[1];
$dbport = $argv[2];
$dbuser = 'root';
$dbpass = '';
$schema = 'upsert';

$dbh = null;
try {
    $dbh = new PDO('mysql:host='.$dbhost.';dbname='.$schema.';port='.$dbport, $dbuser, $dbpass);
} catch (PDOException $e) {
    print "Connection error: " . $e->getMessage()."\n";
    die();
}

while(1){
    $col1 = random(1);
    $col2 = random(4);

    $sql = "INSERT INTO work (col1, col2) VALUES ('".$col1."', '".$col2."') ON DUPLICATE KEY UPDATE col1='".$col1."', col2='".$col2."';";

    $time = microtime(true);
    $stmt = $dbh->exec($sql);

    $dFormat = "H:i:s";
    $mSecs = $time - floor($time);
    $mSecs = substr($mSecs, 1);
    print sprintf('%s%s', date($dFormat), $mSecs)." - ".$stmt." - ".$sql."\n";
    if (!$stmt) {
        $errinfo = $dbh->errorInfo();
        print "    error: ".$errinfo[2]."\n";
    }

    $r = mt_rand(0, 100);
    if($r < 10){
        $sql = "DELETE FROM work;";

        $time = microtime(true);
        $stmt = $dbh->exec($sql);

        $dFormat = "H:i:s";
        $mSecs = $time - floor($time);
        $mSecs = substr($mSecs, 1);
        print sprintf('%s%s', date($dFormat), $mSecs)." - ".$stmt." - ".$sql."\n";
        if (!$stmt) {
            $errinfo = $dbh->errorInfo();
            print "    error: ".$errinfo[2]."\n";
        }
    }
}
$dbh = null;

function random($length)
{
    return substr(str_shuffle('abcd'), 0, $length);
}

