<?php
// (A) SETTINGS
error_reporting(E_ALL & ~E_NOTICE);
//The config.php file declares the following constants for DB connection : DB_HOST, DB_PORT, DB_NAME, DB_USER and DB_PASSWORD
require_once("config.php");

// (B) CONNECT TO DATABASE
try {
  //Creating the PDO object that handles the database connection
  $pdo = new PDO(
    "pgsql:host=" . DB_HOST . ";port=" . DB_PORT . ";dbname=" . DB_NAME,
    DB_USER, DB_PASSWORD
  );
} catch (Exception $ex) { exit($ex->getMessage()); }

//Reading parameters & preparing the matching request :

// (1) for infos - from lon + lat (+ res)
if (isset($_GET['lon'],$_GET['lat'])){
  //These are default values
  $lon = -0.366099;
  $lat = 49.182036;
  //Checking that parameters aren't too long (to prevent some sort of hacking)
  if (strlen($_GET['lon'])<10&&strlen($_GET['lat'])<10){
    $lon = $_GET['lon'];
    $lat = $_GET['lat'];
  }
  // Request : first is default, replaced if some "res" parameter is in the url and does match "maire", "conseillersDptx", ...
  $request_str = "";
  if (isset($_GET['res'])){
    //If there's a "res" parameter :
    if ($_GET['res']=="maire"){
      $request_str = "WITH point AS (SELECT row_number() over() AS id, ST_SetSRID(ST_MakePoint(:lon,:lat),4326) as geom)
                      SELECT concat(c.nom_elu, ' ', c.prenom_elu) as \"Nom du Maire\"
                      FROM point a left join limites_admin.osm_communes b on ST_Intersects(b.geom, ST_Transform(a.geom,2154))
                      left join limites_admin.osm_cantons e on ST_Intersects(ST_pointonsurface(b.geom),e.geom)
                      left join territoire.elus_maires c on c.code = b.insee;";
    }
    elseif ($_GET['res']=="conseillersDptx"){
      $request_str = "WITH point AS (SELECT row_number() over() AS id, ST_SetSRID(ST_MakePoint(:lon,:lat),4326) as geom)
                      SELECT translate(array_agg(concat(' ', d.nom_elu, ' ', d.prenom_elu, ' '))::text, '{\"}','') as \"Nom Conseillers départementaux\"
                      FROM point a
                      left join limites_admin.osm_cantons e on ST_Intersects(ST_Transform(a.geom, 2154),e.geom)
                      left join territoire.elus_conseillers_departementaux d on d.code_canton = e.code
                      group by d.nom_elu, d.prenom_elu;";
    }
    elseif ($_GET['res']=="ptsInfo14"){
      $request_str = "WITH point AS (SELECT row_number() over() AS id, ST_SetSRID(ST_MakePoint(:lon,:lat),4326) as geom)
                      SELECT c.etablissement as \"Points Info 14\", c.voie  as \"Adresse PTI 14\", c.telephone as \"Tel PTI 14\"
                      FROM point a
                      left join limites_admin.osm_calvados b on ST_Intersects(b.geom, ST_Transform(a.geom,2154))
                      left join territoire.inclusion_numerique c on ST_Intersects(b.geom, c.geom) and c.type_structure = 'Point Info 14 / France Services'
                      order by st_distance(ST_Transform(a.geom,2154) ,c.geom)
                      limit 1;";
    }
    elseif ($_GET['res']=="mairies"){
      $request_str = "WITH point AS (SELECT row_number() over() AS id, ST_SetSRID(ST_MakePoint(:lon,:lat),4326) as geom)
                      SELECT concat(d.organisme, '- ' ,d.adresse, '- ', d.telephone) as \"Mairies\"
                      FROM point a left join limites_admin.osm_communes_historiques b on ST_Intersects(b.geom, ST_Transform(a.geom,2154))
                      left join territoire.serv_public_organismes_14 d on ST_Intersects(b.geom, d.geom) and organisme like 'Mairie%';";
    }
    elseif ($_GET['res']=="collegeSecteur"){
      $request_str = "WITH point AS (SELECT row_number() over() AS id, ST_SetSRID(ST_MakePoint(:lon,:lat),4326) as geom)
                      SELECT c.nom as \"Collège du secteur\",  c.adresse as \"Adresse du Collège\", c.site_web as \"Site Web\"
                      FROM point a left join education.colleges_secteurs_osm b on ST_Intersects(b.geom, ST_Transform(a.geom,2154))
                      left join education.colleges_infos c on b.num_etab = c.id_source;";
    }
    elseif ($_GET['res']=="sports"){
      $request_str = "WITH point AS (SELECT row_number() over() AS id, ST_SetSRID(ST_MakePoint(:lon,:lat),4326) as geom),
                      v as (
                        select d.insnom, d.equipementtypelib FROM point a
                        left join limites_admin.osm_communes b on ST_Intersects(b.geom, ST_Transform(a.geom,2154))
                        left join sport.res_equipements d on ST_Intersects(b.geom, d.geom) and  insnom like 'Stade%'
                        group by d.insnom, d.equipementtypelib)
                      SELECT insnom as \"Complexe sportif\" ,translate(array_agg(concat(equipementtypelib, ' '))::text, '{\"}','') as \"types d'équipements\"
                      from v
                      group by insnom;";
    }
  }
  //Setting the request
  $request = $pdo->prepare($request_str);
  //Params :
  $request->bindParam(':lon', $lon);
  $request->bindParam(':lat', $lat);
}

// (2) for communes names and extent - from nom
if (isset($_GET['nom'])){
  $nom = "Caen";
  //Checking that parameters aren't too long (to prevent some sort of hacking)
  if (strlen($_GET['nom'])<42){
    $nom = $_GET['nom'] . "%";//Everything starting by what's in 'nom'
  }
  $request_str = "SELECT nom, ST_Extent(geom) as extent FROM limites_admin.osm_communes WHERE LOWER(nom) LIKE LOWER(:nom) GROUP BY nom;";
  $request = $pdo->prepare($request_str);
  $request->bindParam(':nom', $nom);
}

// (C) GET RESULTS FROM REQUEST

//Execution :
$request->execute();

//Get response :
$response = $request->fetchAll(PDO::FETCH_ASSOC);

//Make it JSON :
$responseJSON = json_encode($response);

//Sending results :
print_r($responseJSON);


// (D) CLOSE DATABASE CONNECTION
$pdo = null;
$request = null;
