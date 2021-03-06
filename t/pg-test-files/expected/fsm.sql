--
-- Free Space Map test
--

SELECT
    current_setting('block_size')::integer AS blocksize,
    current_setting('block_size')::integer / 8 AS strsize \gset

CREATE TABLE fsm_check_size (
    num int,
    str text
);

-- Fill 3 blocks with one record each
ALTER TABLE fsm_check_size SET (fillfactor = 15);

INSERT INTO fsm_check_size
SELECT
    i,
    rpad('', :strsize, 'a')
FROM
    generate_series(1, 3) i;

-- There should be no FSM
VACUUM fsm_check_size;

SELECT
    pg_relation_size('fsm_check_size', 'main') / :blocksize AS heap_nblocks,
    pg_relation_size('fsm_check_size', 'fsm') / :blocksize AS fsm_nblocks;

-- The following operations are for testing the functionality of the local
-- in-memory map. In particular, we want to be able to insert into some
-- other block than the one at the end of the heap, without using a FSM.
-- Fill most of the last block

ALTER TABLE fsm_check_size SET (fillfactor = 100);

INSERT INTO fsm_check_size
SELECT
    i,
    rpad('', :strsize, 'a')
FROM
    generate_series(101, 105) i;

-- Make sure records can go into any block but the last one
ALTER TABLE fsm_check_size SET (fillfactor = 30);

-- Insert large record and make sure it does not cause the relation to extend
INSERT INTO fsm_check_size
    VALUES (111, rpad('', :strsize, 'a'));

VACUUM fsm_check_size;

SELECT
    pg_relation_size('fsm_check_size', 'main') / :blocksize AS heap_nblocks,
    pg_relation_size('fsm_check_size', 'fsm') / :blocksize AS fsm_nblocks;

-- Extend table with enough blocks to exceed the FSM threshold
DO $$
DECLARE
    curtid tid;
    num int;
BEGIN
    num = 11;
    LOOP
        INSERT INTO fsm_check_size
            VALUES (num, 'b')
        RETURNING
            ctid INTO curtid;
        EXIT
        WHEN curtid >= tid '(4, 0)';
        num = num + 1;
    END LOOP;
END;
$$;

VACUUM fsm_check_size;

SELECT
    pg_relation_size('fsm_check_size', 'fsm') / :blocksize AS fsm_nblocks;

-- Add long random string to extend TOAST table to 1 block
INSERT INTO fsm_check_size
    VALUES (0, (
            SELECT
                string_agg(md5(chr(i)), '')
            FROM
                generate_series(1, :blocksize / 100) i));

VACUUM fsm_check_size;

SELECT
    pg_relation_size(reltoastrelid, 'main') / :blocksize AS toast_nblocks,
    pg_relation_size(reltoastrelid, 'fsm') / :blocksize AS toast_fsm_nblocks
FROM
    pg_class
WHERE
    relname = 'fsm_check_size';

DROP TABLE fsm_check_size;

