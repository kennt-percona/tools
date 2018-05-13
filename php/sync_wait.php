<?php

/**
 * Created by .
 * User: hucak
 * Date: 1/27/2018
 * Time: 5:54 PM
 */

/*
 * if connection close of real percona node , get reconnect on proxysql
 */
function getMysqlConn($port=3306) {
    print PHP_EOL."Mysql Reconnection to ".$port;
    $mysqli = new mysqli("127.0.0.1", "root", "", "test", $port);
    $mysqli->query("set SESSION wsrep_sync_wait=1");
    //$mysqli->query("set GLOBAL have_query_cache=NO");
    //$mysqli->query("set GLOBAL query_cache_size=0");
    return $mysqli;
}

$mysqlidb1 = getMysqlConn(4100);
$mysqlidb2 = getMysqlConn(4200);

//$mysqlidb1->autocommit(FALSE);
/* check connection */
if (mysqli_connect_errno()) {
    printf("Connect failed: %s\n", mysqli_connect_error());
    exit();
}


print PHP_EOL . "Truncating table test.ondisk";
$insertSQL = "truncate table test.ondisk";
$stmt = $mysqlidb1->prepare($insertSQL);
if (!$stmt->execute()) {
    $errinfo = $mysqlidb1->errorInfo();
    print PHP_EOL . "Truncate failed : " . $errinfo[2]."\n";
    exit();
}

/* Prepare an insert statement */
$insertSQL = "INSERT INTO test.ondisk (c1,c2) VALUES (?,?)";
$stmt = $mysqlidb1->prepare($insertSQL);
$start = microtime(true);
for ($index = 1; $index <= 1000; $index++) {
    $str = substr(sha1($index), 0, 32);
    //$str = "abcdefghijklmnopqrstuvwxyz";
    if (!$mysqlidb1->ping()) {
        $mysqlidb1 = getMysqlConn(4100);
        $stmt = $mysqlidb1->prepare($insertSQL);
    }
    $mysqlidb1->begin_transaction();
    $stmt->bind_param("ss", $index, $str);
    /* Execute the statement */
    if (!$stmt->execute())
        print PHP_EOL . "INSERT HATASI : " . $mysqlidb1->error;
    if (!$mysqlidb1->commit(MYSQLI_TRANS_START_READ_WRITE))
        print PHP_EOL." Commit Error $index";
    $query = "select * from test.ondisk where c1=$index";
    //usleep(500);
    if (!$mysqlidb2->ping())
        $mysqlidb2 = getMysqlConn(4200);

    if ($result = $mysqlidb2->query($query)) {
        $data = $result->fetch_object();
        if (empty($data->c1)) {
            print PHP_EOL . " ERROR DATA NOT Found $index on 2nd node.";
        }
        $data = null;
        /* free result set */
        $result->close();
    } else
        print PHP_EOL . "RESULT ERROR $index ->" . $mysqlidb2->error;
    if ($index % 100 == 0) {
        print PHP_EOL . "$index Duraction : " . round(microtime(true) - $start, 2);
    }
}
$mysqlidb1->close();
$mysqlidb2->close();
$end = microtime(true);
print PHP_EOL . " Total Duration : " . round($end - $start, 2) .PHP_EOL;
