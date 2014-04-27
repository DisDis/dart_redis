Redis client library
===========

Redis client library, port nodejs node_redis 0.10.1

## Performance
Intel® Core™ i7-3770 CPU @ 3.40GHz × 8
### dart_redis
"str" test slow due to the fact that Dart uses utf-16 for strings. Convert utf16-> utf8 takes lot of time.  nodejs and redis uses utf8 from strings.

    small_buf size:4, small_str size: 4
    large_buf size:4097, large_str size: 4097
    Client count: 5 , dart version: 1.4.0-dev.4.0 (Thu Apr 24 06:38:11 2014) on "linux_x64", server version: 2.8.4, parser: dart     
             PING,     1/5 min/max/avg/p95:    0/   9/   0.07/   1.00   1385ms total,   14440.43 ops/sec     
             PING,    50/5 min/max/avg/p95:    0/   8/   0.59/   2.00    235ms total,   85106.38 ops/sec     
             PING,   200/5 min/max/avg/p95:    0/   6/   1.91/   4.00    192ms total,  104166.67 ops/sec     
             PING, 20000/5 min/max/avg/p95:   10/ 161/  83.83/ 147.55    163ms total,  122699.39 ops/sec     
    SET small str,     1/5 min/max/avg/p95:    0/   5/   0.07/   1.00   1542ms total,   12970.17 ops/sec     
    SET small str,    50/5 min/max/avg/p95:    0/   3/   0.77/   2.00    307ms total,   65146.58 ops/sec     
    SET small str,   200/5 min/max/avg/p95:    0/   7/   2.80/   5.00    281ms total,   71174.38 ops/sec     
    SET small str, 20000/5 min/max/avg/p95:    3/ 220/ 113.49/ 202.00    222ms total,   90090.09 ops/sec     
    SET small buf,     1/5 min/max/avg/p95:    0/   2/   0.07/   1.00   1538ms total,   13003.90 ops/sec     
    SET small buf,    50/5 min/max/avg/p95:    0/   6/   1.20/   3.00    481ms total,   41580.04 ops/sec     
    SET small buf,   200/5 min/max/avg/p95:    0/   7/   2.78/   5.00    279ms total,   71684.59 ops/sec     
    SET small buf, 20000/5 min/max/avg/p95:    4/ 218/ 114.46/ 200.55    220ms total,   90909.09 ops/sec     
    GET small str,     1/5 min/max/avg/p95:    0/   3/   0.07/   1.00   1396ms total,   14326.65 ops/sec     
    GET small str,    50/5 min/max/avg/p95:    0/   5/   1.19/   3.00    476ms total,   42016.81 ops/sec     
    GET small str,   200/5 min/max/avg/p95:    0/   9/   3.19/   7.00    321ms total,   62305.30 ops/sec     
    GET small str, 20000/5 min/max/avg/p95:    3/ 200/ 102.51/ 183.55    202ms total,   99009.90 ops/sec     
    GET small buf,     1/5 min/max/avg/p95:    0/  18/   0.06/   1.00   1316ms total,   15197.57 ops/sec     
    GET small buf,    50/5 min/max/avg/p95:    0/   3/   0.73/   2.00    294ms total,   68027.21 ops/sec     
    GET small buf,   200/5 min/max/avg/p95:    0/   6/   2.65/   5.00    266ms total,   75187.97 ops/sec     
    GET small buf, 20000/5 min/max/avg/p95:    7/ 195/  99.53/ 180.55    197ms total,  101522.84 ops/sec     
    SET large str,     1/5 min/max/avg/p95:    0/   1/   0.10/   1.00   2053ms total,    9741.84 ops/sec     
    SET large str,    50/5 min/max/avg/p95:    0/   7/   1.68/   4.00    673ms total,   29717.68 ops/sec     
    SET large str,   200/5 min/max/avg/p95:    0/  21/   6.43/  12.00    646ms total,   30959.75 ops/sec     
    SET large str, 20000/5 min/max/avg/p95:    3/ 586/ 291.79/ 538.55    588ms total,   34013.61 ops/sec     
    SET large buf,     1/5 min/max/avg/p95:    0/  11/   0.07/   1.00   1396ms total,   14326.65 ops/sec     
    SET large buf,    50/5 min/max/avg/p95:    0/   3/   0.85/   2.00    341ms total,   58651.03 ops/sec     
    SET large buf,   200/5 min/max/avg/p95:    0/   7/   3.12/   6.00    313ms total,   63897.76 ops/sec     
    SET large buf, 20000/5 min/max/avg/p95:    3/ 262/ 134.69/ 244.55    264ms total,   75757.58 ops/sec     
    GET large str,     1/5 min/max/avg/p95:    0/   2/   0.10/   1.00   1963ms total,   10188.49 ops/sec     
    GET large str,    50/5 min/max/avg/p95:    0/   8/   1.83/   5.00    732ms total,   27322.40 ops/sec     
    GET large str,   200/5 min/max/avg/p95:    0/  29/   7.10/  18.00    712ms total,   28089.89 ops/sec     
    GET large str, 20000/5 min/max/avg/p95:  177/ 721/ 447.70/ 691.55    869ms total,   23014.96 ops/sec     
    GET large buf,     1/5 min/max/avg/p95:    0/   2/   0.07/   1.00   1402ms total,   14265.34 ops/sec     
    GET large buf,    50/5 min/max/avg/p95:    0/   4/   0.75/   2.00    299ms total,   66889.63 ops/sec     
    GET large buf,   200/5 min/max/avg/p95:    0/   9/   2.72/   7.00    273ms total,   73260.07 ops/sec     
    GET large buf, 20000/5 min/max/avg/p95:   95/ 184/ 139.95/ 176.00    281ms total,   71174.38 ops/sec     
             INCR,     1/5 min/max/avg/p95:    0/   4/   0.07/   1.00   1518ms total,   13175.23 ops/sec     
             INCR,    50/5 min/max/avg/p95:    0/   4/   0.74/   2.00    298ms total,   67114.09 ops/sec     
             INCR,   200/5 min/max/avg/p95:    0/   7/   2.61/   5.00    262ms total,   76335.88 ops/sec     
             INCR, 20000/5 min/max/avg/p95:    4/ 202/ 103.20/ 182.00    205ms total,   97560.98 ops/sec     
            LPUSH,     1/5 min/max/avg/p95:    0/   1/   0.06/   1.00   1341ms total,   14914.24 ops/sec     
            LPUSH,    50/5 min/max/avg/p95:    0/   3/   0.75/   2.00    300ms total,   66666.67 ops/sec     
            LPUSH,   200/5 min/max/avg/p95:    0/   7/   2.73/   6.00    274ms total,   72992.70 ops/sec     
            LPUSH, 20000/5 min/max/avg/p95:    4/ 212/ 109.16/ 197.00    214ms total,   93457.94 ops/sec     
        LRANGE 10,     1/5 min/max/avg/p95:    0/  10/   0.08/   1.00   1688ms total,   11848.34 ops/sec     
        LRANGE 10,    50/5 min/max/avg/p95:    0/   4/   0.93/   3.00    373ms total,   53619.30 ops/sec     
        LRANGE 10,   200/5 min/max/avg/p95:    0/  10/   3.43/   8.00    344ms total,   58139.53 ops/sec     
        LRANGE 10, 20000/5 min/max/avg/p95:   21/ 306/ 166.99/ 267.00    309ms total,   64724.92 ops/sec     
       LRANGE 100,     1/5 min/max/avg/p95:    0/   2/   0.13/   1.00   2591ms total,    7719.03 ops/sec     
       LRANGE 100,    50/5 min/max/avg/p95:    0/   7/   2.05/   5.00    820ms total,   24390.24 ops/sec     
       LRANGE 100,   200/5 min/max/avg/p95:    0/  21/   7.80/  17.00    783ms total,   25542.78 ops/sec     
       LRANGE 100, 20000/5 Uncaught Error: 
### node_redis
    Client count: 5, node version: 0.10.25, server version: 2.8.4, parser: javascript
             PING,     1/5 min/max/avg/p95:    0/   3/   0.04/   0.00    850ms total,   23529.41 ops/sec
             PING,    50/5 min/max/avg/p95:    0/   5/   1.11/   2.00    446ms total,   44843.05 ops/sec
             PING,   200/5 min/max/avg/p95:    0/   9/   4.28/   7.00    430ms total,   46511.63 ops/sec
             PING, 20000/5 min/max/avg/p95:   19/ 372/ 202.98/ 345.55    377ms total,   53050.40 ops/sec
    SET small str,     1/5 min/max/avg/p95:    0/   3/   0.04/   0.00    821ms total,   24360.54 ops/sec
    SET small str,    50/5 min/max/avg/p95:    0/   3/   1.13/   2.00    454ms total,   44052.86 ops/sec
    SET small str,   200/5 min/max/avg/p95:    0/   9/   4.48/   7.00    450ms total,   44444.44 ops/sec
    SET small str, 20000/5 min/max/avg/p95:   20/ 396/ 210.58/ 359.00    400ms total,   50000.00 ops/sec
    SET small buf,     1/5 min/max/avg/p95:    0/   2/   0.08/   1.00   1720ms total,   11627.91 ops/sec
    SET small buf,    50/5 min/max/avg/p95:    0/   8/   3.32/   5.00   1330ms total,   15037.59 ops/sec
    SET small buf,   200/5 min/max/avg/p95:    0/  27/  13.04/  21.00   1310ms total,   15267.18 ops/sec
    SET small buf, 20000/5 min/max/avg/p95:   63/1354/ 710.11/1284.00   1359ms total,   14716.70 ops/sec
    GET small str,     1/5 min/max/avg/p95:    0/   4/   0.04/   0.00    831ms total,   24067.39 ops/sec
    GET small str,    50/5 min/max/avg/p95:    0/   3/   1.13/   2.00    454ms total,   44052.86 ops/sec
    GET small str,   200/5 min/max/avg/p95:    0/   9/   4.48/   7.00    449ms total,   44543.43 ops/sec
    GET small str, 20000/5 min/max/avg/p95:   23/ 368/ 201.68/ 330.00    375ms total,   53333.33 ops/sec
    GET small buf,     1/5 min/max/avg/p95:    0/   1/   0.04/   0.00    807ms total,   24783.15 ops/sec
    GET small buf,    50/5 min/max/avg/p95:    0/   4/   1.15/   2.00    462ms total,   43290.04 ops/sec
    GET small buf,   200/5 min/max/avg/p95:    1/   9/   4.46/   7.00    448ms total,   44642.86 ops/sec
    GET small buf, 20000/5 min/max/avg/p95:   28/ 380/ 211.57/ 345.00    389ms total,   51413.88 ops/sec
    SET large str,     1/5 min/max/avg/p95:    0/   1/   0.04/   0.00    814ms total,   24570.02 ops/sec
    SET large str,    50/5 min/max/avg/p95:    0/   3/   1.15/   2.00    460ms total,   43478.26 ops/sec
    SET large str,   200/5 min/max/avg/p95:    0/  12/   4.59/   7.00    460ms total,   43478.26 ops/sec
    SET large str, 20000/5 min/max/avg/p95:   23/ 463/ 248.57/ 430.00    468ms total,   42735.04 ops/sec
    SET large buf,     1/5 min/max/avg/p95:    0/   1/   0.09/   1.00   1787ms total,   11191.94 ops/sec
    SET large buf,    50/5 min/max/avg/p95:    0/   7/   3.34/   5.00   1337ms total,   14958.86 ops/sec
    SET large buf,   200/5 min/max/avg/p95:    0/  27/  13.10/  21.00   1317ms total,   15186.03 ops/sec
    SET large buf, 20000/5 min/max/avg/p95:   75/1389/ 737.15/1306.55   1396ms total,   14326.65 ops/sec
    GET large str,     1/5 min/max/avg/p95:    0/   5/   0.04/   0.00    914ms total,   21881.84 ops/sec
    GET large str,    50/5 min/max/avg/p95:    0/   5/   1.34/   3.00    536ms total,   37313.43 ops/sec
    GET large str,   200/5 min/max/avg/p95:    0/  13/   5.44/  10.00    547ms total,   36563.07 ops/sec
    GET large str, 20000/5 min/max/avg/p95:  188/ 333/ 261.06/ 311.00    495ms total,   40404.04 ops/sec
    GET large buf,     1/5 min/max/avg/p95:    0/   7/   0.04/   0.00    836ms total,   23923.44 ops/sec
    GET large buf,    50/5 min/max/avg/p95:    0/  10/   1.29/   2.00    517ms total,   38684.72 ops/sec
    GET large buf,   200/5 min/max/avg/p95:    0/  18/   5.28/  10.00    530ms total,   37735.85 ops/sec
    GET large buf, 20000/5 min/max/avg/p95:  158/ 339/ 250.82/ 310.55    465ms total,   43010.75 ops/sec
             INCR,     1/5 min/max/avg/p95:    0/   8/   0.04/   0.00    787ms total,   25412.96 ops/sec
             INCR,    50/5 min/max/avg/p95:    0/   3/   1.08/   2.00    433ms total,   46189.38 ops/sec
             INCR,   200/5 min/max/avg/p95:    0/   8/   4.18/   7.00    421ms total,   47505.94 ops/sec
             INCR, 20000/5 min/max/avg/p95:   25/ 370/ 202.39/ 339.00    376ms total,   53191.49 ops/sec
            LPUSH,     1/5 min/max/avg/p95:    0/   1/   0.04/   0.00    794ms total,   25188.92 ops/sec
            LPUSH,    50/5 min/max/avg/p95:    0/   3/   1.09/   2.00    438ms total,   45662.10 ops/sec
            LPUSH,   200/5 min/max/avg/p95:    1/  14/   4.49/   7.00    451ms total,   44345.90 ops/sec
            LPUSH, 20000/5 min/max/avg/p95:   24/ 382/ 210.93/ 351.55    389ms total,   51413.88 ops/sec
        LRANGE 10,     1/5 min/max/avg/p95:    0/   2/   0.05/   0.00    949ms total,   21074.82 ops/sec
        LRANGE 10,    50/5 min/max/avg/p95:    0/   4/   1.36/   2.00    545ms total,   36697.25 ops/sec
        LRANGE 10,   200/5 min/max/avg/p95:    1/  15/   5.52/   9.00    554ms total,   36101.08 ops/sec
        LRANGE 10, 20000/5 min/max/avg/p95:   52/ 476/ 269.96/ 429.00    502ms total,   39840.64 ops/sec
       LRANGE 100,     1/5 min/max/avg/p95:    0/   1/   0.11/   1.00   2158ms total,    9267.84 ops/sec
       LRANGE 100,    50/5 min/max/avg/p95:    0/  10/   3.04/   5.00   1220ms total,   16393.44 ops/sec
       LRANGE 100,   200/5 min/max/avg/p95:    1/  25/  11.94/  22.00   1200ms total,   16666.67 ops/sec
       LRANGE 100, 20000/5 min/max/avg/p95:  256/ 875/ 571.66/ 856.00   1111ms total,   18001.80 ops/sec