import random
import string

M = 1024
N = 512*1024
for _ in xrange(M):
    print ''.join(random.choice(string.ascii_uppercase + string.digits) for _ in range(N))
