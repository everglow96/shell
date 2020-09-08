#删除表的规范：必须加上 IF EXISTS
DROP TABLE IF EXISTS oplus.table_a;
#创建表的规范：必须加上 IF NOT EXISTS
CREATE TABLE  IF NOT EXISTS `oplus`.`table_a`( `id` INT(32) NOT NULL AUTO_INCREMENT, PRIMARY KEY (`id`) ) ;

DELIMITER //
DROP PROCEDURE IF EXISTS alter_sql//
CREATE PROCEDURE alter_sql(IN alter_sql VARCHAR(21800))
BEGIN
#把sql中多余的空格去掉
SET @_sql=alter_sql;
WHILE INSTR(@_sql,"  ")>0 DO
	SET @_sql=REPLACE(@_sql, "  ", " ");
END WHILE;

#获取表名@table_name
SET @len=LENGTH(@_sql);
SET @_sql=RIGHT(@_sql,@len-12); #截取alter table 后面的sql
SET @table_name=LEFT(@_sql,INSTR(@_sql," ")-1);

#创建临时表用于储存字段名
DROP TABLE IF EXISTS oplus_tmp_alter;
CREATE TABLE oplus_tmp_alter(action_type VARCHAR(10) , column_name VARCHAR(32));

#获取sql后面主要执行sql:drop xxx,add xxx [type],drop xxx,add xxx [type];
SET @len=LENGTH(@_sql);
SET @_sql=RIGHT(@_sql,@len-INSTR(@_sql," "));
SET @len=LENGTH(@_sql);

WHILE INSTR(@_sql,",") > 0 DO
	#根据","号分割截取action_sql:drop xxx
	SET @action_sql=TRIM(LEFT(@_sql,INSTR(@_sql,",")-1));\
	SET @action_sql=CONCAT(@action_sql," ");    #在drop xxx后增加一个跟空格，使add跟drop兼容下一句的left截取
	SET @type_name=LEFT(@action_sql,LOCATE(" ",@action_sql,6));
	SET @action_type=LEFT(@type_name,INSTR(@type_name," "));
	SET @column_name=RIGHT(@type_name,LENGTH(@type_name)-INSTR(@type_name," "));

	INSERT oplus_tmp_alter(action_type,column_name) VALUE(@action_type,@column_name);
	#截取","号之后的sql:drop xxx,add xxx ... xxx;
	SET @_sql=RIGHT(@_sql,@len-INSTR(@_sql,","));
	SET @len=LENGTH(@_sql);
END WHILE;

#处理最后剩下的drop/add xxx;
SET @action_sql=TRIM(LEFT(@_sql,INSTR(@_sql,";")-1));
SET @action_sql=CONCAT(@action_sql," ");
SET @type_name=LEFT(@action_sql,LOCATE(" ",@action_sql,6));
SET @action_type=LEFT(@type_name,INSTR(@type_name," "));
SET @column_name=RIGHT(@type_name,LENGTH(@type_name)-INSTR(@type_name," "));

INSERT oplus_tmp_alter(action_type,column_name) VALUE(@action_type,@column_name);
#查询有多少字段需要删除(@need_to_drop)
SELECT COUNT(*) INTO @need_to_drop FROM oplus_tmp_alter WHERE action_type="drop";
SELECT COUNT(*) INTO @need_to_add FROM oplus_tmp_alter WHERE action_type="add";
#查询实际存在的需要删除的字段有多少个(@drop_n)
SET @_sql=CONCAT('SELECT COUNT(*) INTO @drop_n FROM information_schema.columns 
			WHERE table_schema ="oplus" 
			AND column_name in(SELECT column_name FROM oplus_tmp_alter WHERE action_type="drop") 
			AND table_name="',@table_name,'";'
		);
PREPARE stmt FROM @_sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
#查询实际存在的需要添加的字段有多少个(@add_n)
SET @_sql=CONCAT('SELECT COUNT(*) INTO @add_n FROM information_schema.columns 
			WHERE table_schema ="oplus" 
			AND column_name in(SELECT column_name FROM oplus_tmp_alter WHERE action_type="add") 
			AND table_name="',@table_name,'";'
		);
PREPARE stmt FROM @_sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

#SELECT @drop_n,@need_to_drop,@add_n,@need_to_add;
#当需要表格不存在需要添加的字段,且需要删除的字段数量@need_to_drop跟已存在的字段数量@drop_n一致时执行sql
IF (@add_n = 0 AND @need_to_drop = @drop_n) THEN
	#select @drop_n as drop_n,@need_to_drop as need_to_drop,@add_n as add_n;
	SET @_sql=alter_sql;
	PREPARE stmt FROM @_sql;
	EXECUTE stmt;
	DEALLOCATE PREPARE stmt;
END IF;
#删除临时表
DROP TABLE IF EXISTS oplus_tmp_alter;
END //
DELIMITER ;

#执行方式call alter_sql(增加/删除表字段的sql)
CALL alter_sql("alter table table_a drop column_d ,add column_f varchar(30),add column_g varchar(30);");
