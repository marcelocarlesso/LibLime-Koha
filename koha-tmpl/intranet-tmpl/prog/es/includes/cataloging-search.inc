
<h1 id="logo"><a href="/cgi-bin/koha/mainpage.pl"><!-- TMPL_VAR NAME="LibraryName" --></a></h1><!-- Begin Cataloging Resident Search Box -->
<div id="header_search">
<div id="addbooks_search" class="residentsearch">
	<p class="tip">Buscar en el cat&aacute;logo y el depósito:</p>
	<form name="search" action="addbooks.pl">
        <input type="text" name="q"  size="40" class="focus" />
        <input type="submit" class="submit" value="Enviar">
	</form>
</div>
    <!-- TMPL_INCLUDE NAME="patron-search-box.inc" -->
			<ul>
			<li><a href="/cgi-bin/koha/catalogue/search.pl#addbooks_search">Búsqueda en el catálogo</a></li>
			<!-- TMPL_IF NAME="CAN_user_circulate" --><li><a href="/cgi-bin/koha/circ/circulation.pl#circ_search">Préstamo</a></li><!-- /TMPL_IF -->
			</ul>	
</div>
<!-- End Cataloging Resident Search Box -->
