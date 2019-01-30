*************************************************************************************************
*       PROGRAM NAME:   _gen_meta.sas
*        SAS VERSION:   9.1.3 / 9.2 (Windows)
*            PURPOSE:   Output the metadata for Post Processing mapping specs                       
*
*        USAGE NOTES:   PC SAS submit
*        INPUT FILES:  
*       OUTPUT FILES:  METADATA
*
*             AUTHOR:   Lu Zhang
*       DATE CREATED:   01Apr2015
*         PARAMETERS:  LIBIN : Library of staged datasets
*                                  (Defaults to STAGEDR)
*                       SDS_IN  : SDS file to read in.
*		    	 METADATA: Output Metadata
*								   (Defaults to HERE.PPR_METADATA)
*
*   MODIFICATION LOG:
*************************************************************************************************
* DATE         BY          DESCRIPTION
*************************************************************************************************
* © 2015 Pharmaceutical Product Development, Inc.
* All Rights Reserved.
*************************************************************************************************;


%macro _gen_meta(libin=STAGEDR, 
				 sds_in=SDS_SHORT.xls, 
				 metadata=here.ppr_metadata);

	%let err = E%str(RROR: );

	%*** CHECK PARAMETER ***;
	%if %sysfunc(libref(&libin)) ne 0 %then %do; 
	   %put &err. The library &libin does not exist, please check.;
	   %goto err; 
	%end;
	
	%if %sysfunc(fileexist(&sds_in.)) = 0 %then %do;
	  %put &err. The SDS file can not be found, please check.;
	  %goto err;
	%end;


	%*** READIN SDS VARIABLE INFORAMTION ***;
	libname _sds excel "&sds_in.";

	data _fields;
		set _sds.'Fields$'n;
	run;

	libname _sds clear;

	%*** MODIFY SPEC DATA BASED ON POST PROCESSING GUIDE ***;
	data _mod_fields;
		set _fields;
		memname=compress(formoid,,'d');
		name=variableoid;
		_coding=codingdictionary;
		_unit=unitdictionaryname;
		_codelst=datadictionaryname;
		_type=controltype;
		if name ne '';
		filed=1;
		keep memname name _coding _unit _codelst _type filed;
	run;

	proc sort data=_mod_fields nodupkeys;
		by memname name;
	run;

	proc sql;
		create table _curr_data as
		select memname length=200 as memname, upcase(name) length=200 as name, label, 
		       type, compress(put(length,best12.)) length=200 as length, format, varnum
		from dictionary.columns
		where libname = "&libin."
		order by memname, varnum;

		create table _currd as
		select a.*, b._coding, b._unit, b._codelst, b._type, b.filed
		from _curr_data a left join _mod_fields b on compress(a.memname,,'d')=b.memname and scan(a.name,1,'_')=b.name
		order by memname, varnum;
	quit;

	data &metadata.;
		set _currd;
		length calc $200;
		memname2=memname;
		name=upcase(name);
		_type=upcase(_type);
		outname=name;
		outlabel=label;
		outtype=type;
		outlength=length;
		outformat=format;
		outtype=type;

		if type='char' then do;
			if input(compress(outlength,,'kd'),best.)>200 then do;
				outlength='200';
				outformat='$200.';
			end;
			if input(compress(outlength,,'kd'),best.) ne input(compress(outformat,,'kd'),best.) then outformat=cats('$',outlength,'.');
		end;

		%*** LOCAL LAB VARIABLES RENAME ***;
			
		if substr(name,1,5)='LBRES' /*and anydigit(name)*/ then do;
			outname=tranwrd(name,'LBRES','LBRS');
			outname=tranwrd(outname,'_U','U');
		end;

		%*** Check Box Variables ***;
		if _type='CHECKBOX' then do;
			outname=strip(name)||'N';
			output;
			outtype='char';
			calc='Apply following format to '||strip(outname)||': 0=Not Checked; 1=Chekced';
			outname=strip(name);
			call missing(memname,name,label,type,length,format,type);
			output;
		end;
		%*** UNITS ***;
		else if _unit ne '' then do;
			if index(name,'_CV') then do;
				outname=strip(scan(name,1,'_'))||'SN';
				outlabel=tranwrd(label, 'Code', ' Standard Value');
				output;
			end;		
			else if index(name,'_U') or index(name,'_SU') then do;
				outname=compress(name,'_');
				output;
				outname=strip(outname)||'N';
				outlabel=strip(label)||' -num';
				calc='Convert '||strip(name)||' to numeric value';
				outtype='num';
				call missing(memname,name,label,type,length,format,type);
				output;
			end;
			else if type='num' then do;
				outlabel=strip(label)||' -num';
				output;
				outname=strip(name)||'F';
				outlabel=strip(label);
				outtype='char';
				calc='Convert numeric to character';
				outlength='200';
				outformat='$200.';
				call missing(memname,name,label,type,length,format,type);
				output;
			end;
			else if type='char' then do;
				outname=strip(name)||'F';
				output;
				outname=strip(name);
				outlabel=strip(label)||' -num';
				outtype='num';
				outlength='8';
				outformat='best.';
				calc='Convert character to numeric';
				call missing(memname,name,label,type,length,format,type);
				output;
			end;
		end;
		%*** CODING VARIABLES ***;
		else if index(_coding,'MedDRA') then do;
			if index(name,'_CODE') then outname=strip(scan(name,2,'_'))||'CD';
			else if index(name,'_') then outname=strip(scan(name,2,'_'))||'NM';
			if outlength='90' then do;
				outlength='60';
				outformat='$60.';
			end;
			output;
			if outname='SOCCD' then do;
				outname='DIVER';
				outlabel='Dictionary Version';
				outtype='char';
				outlength='200';
				outformat='$200.';
				calc='Set to "MedDRA XXX"';
				call missing(memname,name,label,type,length,format,type);
				output;
			end;
		end;
		else if index(_coding,'WhoDrug') then do;
			if outlength='90' then do;
				outlength='60';
				outformat='$60.';
			end;
			if index(name,'PREFERRED_CODE') then do;
				outname='PNCD';
				outlabel='Preferred Drug Name Code';
			end;
			else if index(name,'PREFERRED') then do;
				outname='PN';
				outlabel='Preferred Drug Name';
			end;
			else if index(name,'_') then flag='D';
			output;
			if index(name,'TRADE_CODE') then do;
				call missing(memname,name,label,type,length,format,type,flag);
				do tmp='ATC1', 'ATC2', 'ATC3', 'ATC4', 'SYN';
					outname=tmp;
					outlabel=strip(tmp)||' Term';
					outlength='200';
					outformat='$200.';
					output;
					outname=strip(tmp)||'CD';
					outlabel=strip(tmp)||' Code';
					if tmp='SYN' then do;
						outlength='60';
						outformat='$60.';
					end;
					output;
				end;
				outname='DIVER';
				outlabel='Dictionary Version';
				outtype='char';
				outlength='200';
				outformat='$200.';
				calc='Set to "MedDRA XXX"';
				output;
			end;
		end;
		%*** DICTIONARY ASSOCIATED ***;
		else if _codelst ne '' then do;
			if index(name,'_CV') then outname=strip(scan(name,1,'_'))||'N';
			outlabel=tranwrd(label,'Coded Value',' -num');
			output;
		end;
		%*** Incase missing Dictionary ***;
		else if index(name,'_CV') then do;
			outname=strip(scan(name,1,'_'))||'N';
			outlabel=tranwrd(label,'Coded Value',' -num');
			output;
		end;

		%*** TIME FIELD ***;
		else if _type='DATETIME' and substr(name,length(name)-1)='TM' then do;
			outlabel=strip(label)||' -num';
			outlength='8';
			outformat='TIME5.';
			outtype='num';
			output;
			outlabel=strip(label)||' -char';
			outlength='11';
			outformat='$11.';
			outtype='char';
			outname=strip(name)||'FF';
			call missing(memname,name,label,type,length,format,type);
			output;
		end;

		else if _type='TEXT' then do;
			output;
			%*** NUMERIC FIELDS THAT DO NOT HAVE ASSOCIATE CODELIST ***;
			if type='num' /*and memname not in ('HEMA' 'CHEM' 'URIN')*/ then do;
				outtype='char';
				outname=strip(name)||'F';
				outlabel=strip(label)||' -char';
				outlength='200';
				outformat='$200.';
				calc='Convert numeric to character';
				call missing(memname,name,label,type,length,format,type);
				output;
			end;
		end;
		else do;		
			%*** DROP SPLITTED DATE VARIABLES ***;
			if substr(name,length(name)-1) in ('_D' '_M' '_C' '_Y') then flag='D';
			output;
		end;
		drop _: tmp;	
	run;
%err:
%mend;
