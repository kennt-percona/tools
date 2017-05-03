/* Test case for testing Galera multi-master to ensure data consistency for
 * record updates coming from multiple servers.
 * Based partially on information obtained from:
 *   http://galeracluster.com/2015/09/support-for-mysql-transaction-isolation-levels-in-galera-cluster/
 * This is intended to be run through a load balancer like HAProxy or Linux IPVS/LVS
 * round-robining connections to different servers.
 * 
 * NOTE: It seems that this script can cause the connections on the DB server to
 *       hang indefinitely.  "SHOW PROCESSLIST;" on each db node does not show any
 *       active queries for the hung connections, but they never received a response.
 *       Restarting the MySQL daemon causes the connections to 'unhang' on the
 *       client side.   The issue DOES NOT occur when connecting to a single node.
 * 
 * NOTE 2: If you are testing this script *correctly*, then you should see some lines
 *         output when deadlocks occur, this is normal and fully expected!.  If you
 *         do NOT see this, then that means you are probably only running this against
 *         a single node.
 * 
 * Compiling:
 *   gcc -Wall -W -Os -o galera_test galera_test.c -lmysqlclient_r -lpthread
 * 
 * Running:
 *    ./galera_test "host1 host2 host3" "user" "pass" "dbname"
 */

#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <mysql/mysql.h>
#include <errno.h>

static       char **HOSTS     = NULL;
size_t              NUM_HOSTS = 0;
static const char  *USER      = NULL;
static const char  *PASS      = NULL;
static const char  *DB        = NULL;
#define NUM_THREADS          25
#define NUM_TASKS_PER_THREAD 1000


size_t          counter = 0;
pthread_mutex_t mutex   = PTHREAD_MUTEX_INITIALIZER;


static void counter_inc(void)
{
	pthread_mutex_lock(&mutex);
	counter++;
	pthread_mutex_unlock(&mutex);
}


static size_t counter_get(void)
{
	size_t ret;
	pthread_mutex_lock(&mutex);
	ret = counter;
	pthread_mutex_unlock(&mutex);
	return ret;
}


static int mysql_is_rollback_error(int err)
{
	switch (err) {
		case 1205: /* ER_LOCK_WAIT_TIMEOUT */
		case 1206: /* ER_LOCK_TABLE_FULL */
		case 1213: /* ER_LOCK_DEADLOCK */
		/* NOTE: unclear this error code should have been returned with galera, we
		         need to treat this as a rollback-able event otherwise we can get
		         consistency issues */
		case 1317: /* ER_QUERY_INTERRUPTED */
			return 1;
		default:
			fprintf(stderr, "Received additional error : %d", err);
	}
	return 0;
}


static int run_txn(MYSQL *mysql, size_t threadid)
{
	int         rollback = 0;
	MYSQL_BIND  bind[2];
	MYSQL_BIND  rbind[1];
	MYSQL_STMT *stmt;
	int         id       = 1;
	int         val      = 0;
	MYSQL_RES  *prepare_meta_result;

#define SELECT_STMT "SELECT bar FROM foo WHERE id = ? FOR UPDATE"
#define UPDATE_STMT "UPDATE foo SET bar = ? WHERE id = ?"

	do {
		if (rollback) {
			/* Ignroe rollback failures, shouldn't fail, right? */
			if (mysql_query(mysql, "ROLLBACK") != 0) {
				fprintf(stderr, "WARN [%zu] ROLLBACK failed: %s\n", threadid, mysql_error(mysql));
			}
			usleep(random() % 50000);
		}
		rollback = 0;

		/* == BEGIN == */
		if (mysql_query(mysql, "BEGIN") != 0) {
			fprintf(stderr, "ERROR [%zu] BEGIN failed: %s\n", threadid, mysql_error(mysql));
			return 0;
		}

		/* == SELECT bar FROM foo WHERE id = ? FOR UPDATE == */
		stmt = mysql_stmt_init(mysql);
		if (mysql_stmt_prepare(stmt, SELECT_STMT, strlen(SELECT_STMT)) != 0) {
			if (mysql_is_rollback_error(mysql_stmt_errno(stmt))) {
				fprintf(stderr, "[%zu] SELECT prepare ROLLBACK: %s\n", threadid, mysql_stmt_error(stmt));
				mysql_stmt_close(stmt); stmt = NULL;
				rollback = 1;
				continue;
			}
			fprintf(stderr, "ERROR [%zu] SELECT prepare failed: %s\n", threadid, mysql_stmt_error(stmt));
			return 0;
		}
		memset(bind, 0, sizeof(bind));
		bind[0].buffer_type = MYSQL_TYPE_LONG;
		bind[0].buffer      = (char *)&id;
		if (mysql_stmt_bind_param(stmt, bind) != 0) {
			fprintf(stderr, "ERROR [%zu] SELECT bind failed: %s\n", threadid, mysql_stmt_error(stmt));
			return 0;
		}

		prepare_meta_result = mysql_stmt_result_metadata(stmt);
		if (!prepare_meta_result) {
			fprintf(stderr, "ERROR [%zu] Unable to get result metadata: %s\n", threadid, mysql_stmt_error(stmt));
			return 0;
		}
		if (mysql_num_fields(prepare_meta_result) != 1) {
			fprintf(stderr, "ERROR [%zu] expected 1 result column, got %d\n", threadid, (int)mysql_num_fields(prepare_meta_result));
			return 0;
		}

		if (mysql_stmt_execute(stmt) != 0) {
			if (mysql_is_rollback_error(mysql_stmt_errno(stmt))) {
				fprintf(stderr, "[%zu] SELECT ROLLBACK: %s\n", threadid, mysql_stmt_error(stmt));
				mysql_stmt_close(stmt); stmt = NULL;
				rollback = 1;
				continue;
			}
			fprintf(stderr, "ERROR [%zu] SELECT FAILED: %s\n", threadid, mysql_stmt_error(stmt));
			return 0;
		}

		val = 0;
		memset(rbind, 0, sizeof(rbind));
		rbind[0].buffer_type = MYSQL_TYPE_LONG;
		rbind[0].buffer      = (char *)&val;
		if (mysql_stmt_bind_result(stmt, rbind) != 0) {
			fprintf(stderr, "ERROR [%zu] SELECT result bind failed: %s\n", threadid, mysql_stmt_error(stmt));
			return 0;
		}

		if (mysql_stmt_fetch(stmt) != 0) {
			fprintf(stderr, "ERROR [%zu] SELECT fetch failed: %s\n", threadid, mysql_stmt_error(stmt));
			return 0;
		}

		mysql_free_result(prepare_meta_result);
		mysql_stmt_close(stmt); stmt = NULL;

		/* MATH ON 'val' */
		val++;

		/* == UPDATE foo SET bar = ? WHERE id = ? == */
		stmt = mysql_stmt_init(mysql);
		if (mysql_stmt_prepare(stmt, UPDATE_STMT, strlen(UPDATE_STMT)) != 0) {
			if (mysql_is_rollback_error(mysql_stmt_errno(stmt))) {
				fprintf(stderr, "[%zu] UPDATE prepare ROLLBACK: %s\n", threadid, mysql_stmt_error(stmt));
				mysql_stmt_close(stmt); stmt = NULL;
				rollback = 1;
				continue;
			}
			fprintf(stderr, "ERROR [%zu] UPDATE prepare failed: %s\n", threadid, mysql_stmt_error(stmt));
			return 0;
		}
		memset(bind, 0, sizeof(bind));
		bind[0].buffer_type = MYSQL_TYPE_LONG;
		bind[0].buffer      = (char *)&val;
		bind[1].buffer_type = MYSQL_TYPE_LONG;
		bind[1].buffer      = (char *)&id;
		if (mysql_stmt_bind_param(stmt, bind) != 0) {
			fprintf(stderr, "ERROR [%zu] UPDATE bind failed: %s\n", threadid, mysql_stmt_error(stmt));
			return 0;
		}

		if (mysql_stmt_execute(stmt) != 0) {
			if (mysql_is_rollback_error(mysql_stmt_errno(stmt))) {
				fprintf(stderr, "[%zu] UPDATE ROLLBACK: %s\n", threadid, mysql_stmt_error(stmt));
				mysql_stmt_close(stmt); stmt = NULL;
				rollback = 1;
				continue;
			}
			fprintf(stderr, "ERROR [%zu] UPDATE FAILED: %s\n", threadid, mysql_stmt_error(stmt));
			return 0;
		}

		if (mysql_stmt_affected_rows(stmt) != 1) {
			fprintf(stderr, "ERROR [%zu] expected 1 row to be updated, instead %d updated: %s\n", threadid, (int)mysql_stmt_affected_rows(stmt), mysql_stmt_error(stmt));
			return 0;
		}

		mysql_stmt_close(stmt); stmt = NULL;

		/* == COMMIT == */
		if (mysql_query(mysql, "COMMIT") != 0) {
			if (mysql_is_rollback_error(mysql_errno(mysql))) {
				fprintf(stderr, "[%zu] COMMIT ROLLBACK: %s\n", threadid, mysql_error(mysql));
				rollback = 1;
				continue;
			}
			fprintf(stderr, "ERROR [%zu] COMMIT failed: %s\n", threadid, mysql_error(mysql));
			return 0;
		}
	} while(rollback);

	/* Successful, increment counter */
	counter_inc();

	return 1;
}


static int db_connect(MYSQL *mysql, size_t threadid)
{
	unsigned int arg;
    unsigned int port = 0;
    char *       host = strdup(HOSTS[threadid % NUM_HOSTS]);
    char *       sep;

    /* parse the host string into address and port if it contains a ':' */
    if ((sep = strchr(host, ':')) != NULL) {
        *sep = '\0';
        port = atoi(sep+1);
    }
    
	mysql_init(mysql);
	arg = MYSQL_PROTOCOL_TCP;
	mysql_options(mysql, MYSQL_OPT_PROTOCOL, &arg);
	printf("[%zu] connecting to %s\n", threadid, HOSTS[threadid % NUM_HOSTS]);
	if (!mysql_real_connect(mysql, host, USER, PASS, DB, port, NULL, 0)) {
		fprintf(stderr, "[%zu] ERROR Failed to connnect to %s:%d: %s\n", threadid, host, port, mysql_error(mysql));
		mysql_close(mysql);
        free(host);
		return 0;
	}

	/* NOTE: we know that Galera doesn't support SERIALIZABLE, however in theory
	 *       we should not be relying on this isolation level anyhow due to 
	 *       Select For Update (for single node protection) and Galera's
	 *       certification process for cross-node record consistency */
	if (mysql_query(mysql, "SET SESSION TRANSACTION ISOLATION LEVEL SERIALIZABLE") != 0) {
		fprintf(stderr, "ERROR SET SERIALIZABLE failed: %s\n", mysql_error(mysql));
		mysql_close(mysql);
        free(host);
		return 0;
	}
    free(host);
	return 1;
}


static void *thread_task(void *arg)
{
	size_t i;
	MYSQL  mysql;
	size_t threadid = (size_t)arg;

	(void)arg;

	sched_yield();

	if (mysql_thread_init() != 0) {
		fprintf(stderr, "ERROR [%zu] failed to init threading", threadid);
		return (void *)1;
	}

	if (!db_connect(&mysql, threadid))  {
		fprintf(stderr, "ERROR [%zu] failed to connect", threadid);
		return (void *)1;
	}

	for (i=0; i<NUM_TASKS_PER_THREAD; i++) {
		if (!run_txn(&mysql, threadid)) {
			mysql_close(&mysql);
			mysql_thread_end();
			return (void *)1;
		}
	}

	fprintf(stderr, "[%zu] DONE - %zu confirmed incremented\n", threadid, counter_get());
	mysql_close(&mysql);
	mysql_thread_end();
	return NULL;
}


static char **hosts_to_array(char *hosts, const char *delim, size_t *num)
{
	char **ret     = NULL;
	char  *saveptr = NULL;

	*num = 0;

	while (1) {
		char *host = strtok_r(hosts, delim, &saveptr);
		hosts      = NULL; /* Set to NULL after first iteration */
		if (host == NULL || strlen(host) == 0)
			break;

		ret       = realloc(ret, sizeof(*ret) * ((*num)+1));
		ret[*num] = strdup(host);
		(*num)++;
	}

	return ret;
}


int main(int argc, char **argv)
{
	MYSQL      conn;
	pthread_t  thread[NUM_THREADS];
	size_t     i;
	MYSQL_ROW  row;
	MYSQL_RES *res;

	if (argc != 5) {
		printf("usage: %s \"HOST1 ... HOSTN\" \"USER\" \"PASS\" \"DB\"\n", argv[0]);
		return 1;
	}

	USER  = argv[2];
	PASS  = argv[3];
	DB    = argv[4];

	HOSTS = hosts_to_array(argv[1], " ", &NUM_HOSTS);
	if (NUM_HOSTS == 0) {
		fprintf(stderr, "ERROR no hosts specified");
		return 1;
	}

	if (mysql_library_init(0, NULL, NULL) != 0) {
		fprintf(stderr, "ERROR mysql_library_init failed\n");
		return 1;
	}

	if (!db_connect(&conn, NUM_THREADS)) {
		return 1;
	}

	/* DROP TABLE IF EXISTS foo */
	if (mysql_query(&conn, "DROP TABLE IF EXISTS foo") != 0) {
		fprintf(stderr, "ERROR DROP TABLE failed: %s\n", mysql_error(&conn));
		return 1;
	}

	/* CREATE TABLE foo (id INTEGER, bar INTEGER, PRIMARY KEY(id)) */
	if (mysql_query(&conn, "CREATE TABLE foo (id INTEGER, bar INTEGER, PRIMARY KEY(id))") != 0) {
		fprintf(stderr, "ERROR CREATE TABLE failed: %s\n", mysql_error(&conn));
		return 1;
	}

	/* INSERT INTO foo VALUES (1, 0) */
	if (mysql_query(&conn, "INSERT INTO foo VALUES (1, 0)") != 0) {
		fprintf(stderr, "ERROR INSERT INTO foo failed: %s\n", mysql_error(&conn));
		return 1;
	}

	/* Spawn threads */
	for (i=0; i<NUM_THREADS; i++) {
		if (pthread_create(&thread[i], NULL, thread_task, (void *)i) != 0) {
			fprintf(stderr, "ERROR FAILED TO SPAWN THREAD %zu: %s\n", i, strerror(errno));
			return 1;
		}
		printf("[%zu] thread spawned\n", i);
	}

	/* Wait for threads to exit */
	for (i=0; i<NUM_THREADS; i++) {
		void *retval = NULL;
		if (pthread_join(thread[i], &retval) != 0) {
			fprintf(stderr, "ERROR FAILED TO join thread %zu: %s\n", i, strerror(errno));
			return 1;
		}
		printf("[%zu] parent reading thread result\n", i);
		if (retval != NULL) {
			fprintf(stderr, "ERROR Thread %zu reported failure\n", i);
			return 1;
		}
	}

	printf("Validating final result...\n");

	/* Get final result */
	if (mysql_query(&conn, "SELECT bar FROM foo WHERE id = 1") != 0) {
		fprintf(stderr, "ERROR FINAL SELECT failed: %s\n", mysql_error(&conn));
		return 1;
	}

	res = mysql_store_result(&conn);
	if (res == NULL || mysql_num_fields(res) != 1) {
		fprintf(stderr, "ERROR failed to store result: %s\n", mysql_error(&conn));
		return 1;
	}
	
	row = mysql_fetch_row(res);
	if (row == NULL) {
		fprintf(stderr, "ERROR failed to fetch row in result\n");
		return 1;
	}

	if (atoi(row[0]) != NUM_THREADS * NUM_TASKS_PER_THREAD) {
		printf("ERROR Final count %d does not match expected count %d\n", atoi(row[0]), (int)NUM_THREADS * NUM_TASKS_PER_THREAD);
		return 1;
	}

	mysql_free_result(res);

	printf("SUCCESS\n");
	mysql_close(&conn);
	return 0;
}


