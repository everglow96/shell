#ɾ����Ĺ淶��������� IF EXISTS
DROP TABLE IF EXISTS oplus.table_a;
#������Ĺ淶��������� IF NOT EXISTS
CREATE TABLE  IF NOT EXISTS `oplus`.`table_a`( `id` INT(32) NOT NULL AUTO_INCREMENT, PRIMARY KEY (`id`) ) ;

DELIMITER //
DROP PROCEDURE IF EXISTS alter_sql//
CREATE PROCEDURE alter_sql(IN alter_sql VARCHAR(21800))
BEGIN
#��sql�ж���Ŀո�ȥ��
SET @_sql=alter_sql;
WHILE INSTR(@_sql,"  ")>0 DO
	SET @_sql=REPLACE(@_sql, "  ", " ");
END WHILE;

#��ȡ����@table_name
SET @len=LENGTH(@_sql);
SET @_sql=RIGHT(@_sql,@len-12); #��ȡalter table �����sql
SET @table_name=LEFT(@_sql,INSTR(@_sql," ")-1);

#������ʱ�����ڴ����ֶ���
DROP TABLE IF EXISTS oplus_tmp_alter;
CREATE TABLE oplus_tmp_alter(action_type VARCHAR(10) , column_name VARCHAR(32));

#��ȡsql������Ҫִ��sql:drop xxx,add xxx [type],drop xxx,add xxx [type];
SET @len=LENGTH(@_sql);
SET @_sql=RIGHT(@_sql,@len-INSTR(@_sql," "));
SET @len=LENGTH(@_sql);

WHILE INSTR(@_sql,",") > 0 DO
	#����","�ŷָ��ȡaction_sql:drop xxx
	SET @action_sql=TRIM(LEFT(@_sql,INSTR(@_sql,",")-1));\
	SET @action_sql=CONCAT(@action_sql," ");    #��drop xxx������һ�����ո�ʹadd��drop������һ���left��ȡ
	SET @type_name=LEFT(@action_sql,LOCATE(" ",@action_sql,6));
	SET @action_type=LEFT(@type_name,INSTR(@type_name," "));
	SET @column_name=RIGHT(@type_name,LENGTH(@type_name)-INSTR(@type_name," "));

	INSERT oplus_tmp_alter(action_type,column_name) VALUE(@action_type,@column_name);
	#��ȡ","��֮���sql:drop xxx,add xxx ... xxx;
	SET @_sql=RIGHT(@_sql,@len-INSTR(@_sql,","));
	SET @len=LENGTH(@_sql);
END WHILE;

#�������ʣ�µ�drop/add xxx;
SET @action_sql=TRIM(LEFT(@_sql,INSTR(@_sql,";")-1));
SET @action_sql=CONCAT(@action_sql," ");
SET @type_name=LEFT(@action_sql,LOCATE(" ",@action_sql,6));
SET @action_type=LEFT(@type_name,INSTR(@type_name," "));
SET @column_name=RIGHT(@type_name,LENGTH(@type_name)-INSTR(@type_name," "));

INSERT oplus_tmp_alter(action_type,column_name) VALUE(@action_type,@column_name);
#��ѯ�ж����ֶ���Ҫɾ��(@need_to_drop)
SELECT COUNT(*) INTO @need_to_drop FROM oplus_tmp_alter WHERE action_type="drop";
SELECT COUNT(*) INTO @need_to_add FROM oplus_tmp_alter WHERE action_type="add";
#��ѯʵ�ʴ��ڵ���Ҫɾ�����ֶ��ж��ٸ�(@drop_n)
SET @_sql=CONCAT('SELECT COUNT(*) INTO @drop_n FROM information_schema.columns 
			WHERE table_schema ="oplus" 
			AND column_name in(SELECT column_name FROM oplus_tmp_alter WHERE action_type="drop") 
			AND table_name="',@table_name,'";'
		);
PREPARE stmt FROM @_sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
#��ѯʵ�ʴ��ڵ���Ҫ��ӵ��ֶ��ж��ٸ�(@add_n)
SET @_sql=CONCAT('SELECT COUNT(*) INTO @add_n FROM information_schema.columns 
			WHERE table_schema ="oplus" 
			AND column_name in(SELECT column_name FROM oplus_tmp_alter WHERE action_type="add") 
			AND table_name="',@table_name,'";'
		);
PREPARE stmt FROM @_sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

#SELECT @drop_n,@need_to_drop,@add_n,@need_to_add;
#����Ҫ��񲻴�����Ҫ��ӵ��ֶ�,����Ҫɾ�����ֶ�����@need_to_drop���Ѵ��ڵ��ֶ�����@drop_nһ��ʱִ��sql
IF (@add_n = 0 AND @need_to_drop = @drop_n) THEN
	#select @drop_n as drop_n,@need_to_drop as need_to_drop,@add_n as add_n;
	SET @_sql=alter_sql;
	PREPARE stmt FROM @_sql;
	EXECUTE stmt;
	DEALLOCATE PREPARE stmt;
END IF;
#ɾ����ʱ��
DROP TABLE IF EXISTS oplus_tmp_alter;
END //
DELIMITER ;

#ִ�з�ʽcall alter_sql(����/ɾ�����ֶε�sql)
CALL alter_sql("alter table table_a drop column_d ,add column_f varchar(30),add column_g varchar(30);");
