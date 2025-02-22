module View exposing (..)

import DataSourceForm exposing (datasourceForm)
import Model exposing (..)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick)
import Messages exposing (..)

dataSourceItem : DataSource -> Html Msg
dataSourceItem datasource =
  li [ onClick (SelectDataSource datasource ) ] [
      h4 [ class "no-margin" ] [
        span [] [ text datasource.name ]
      ]
    , div [ class "detail-datasource"] [ text datasource.id ]
    , div [ class "description-datasource" ] [ text datasource.description ]
    ]

view: Model -> Html Msg
view model =
  let
    ui = model.ui
  in
  div [ class "rudder-template", id "datasource" ] [
    div [ class "template-sidebar sidebar-left" ] [
      div [ class "sidebar-header" ] [
        div [ class "header-title" ] [
          h1 [] [
            span [] [ text "Data sources" ]
          ]
        ]
      , div [ class "header-buttons" ] [
          button [ class "btn btn-success", onClick NewDataSource ] [
            text "Add data source "
          , i [ class "add-icon ion ion-android-add-circle" ] []
          ]
        ]
      ]
    , div [ class "sidebar-body" ] [
          div [ class "sidebar-list", id "datasources-tree" ] [
            ul [ ]
             (List.map   dataSourceItem model.dataSources)

          ]
        ]

      ]


  , div [ class "template-main" ] [
      ( case model.mode of
        Init ->
          div [ class "jumbotron jumbotron-datasource"] [
            h1 [] [text "Node properties data sources"]
          , p [] [
              text """Nodes have properties that can be used to create groups or in techniques and directives parameters.
              These properties are b [] [key/value] pairs, where values can be a simple string or a well formed JSON document."""
            ]
          , p [] [
              text "You can automatically import node properties by creating data sources that will query a third party REST API to retrieve data and it in a given property key for each node it's available for."
            ]
          , p [] [
              button [ class "btn btn-success btn-lg", type_ "button", onClick NewDataSource ] [
              text "Add data source "
            , i [ class "add-icon ion ion-android-add-circle" ] []
            ]
          ]
          ]
        ShowDatasource source origin ->
          datasourceForm model source origin
     )
     ]



  , case model.ui.deleteModal of
      Just datasource ->
        div [ class "modal fade datasource-modal", id "deleteModal", tabindex -1] [ -- role "dialog" ] [
          div [ class "modal-dialog"] [ -- role "document" ] [
            div [ class "modal-content" ] [
            div [ class "modal-header" ] [
              button [ type_ "button", class "close", onClick (UpdateUI {ui | deleteModal = Nothing}) ] [
                span [] [ --aria-hidden "true", [] [
                  text "&times;"
                ]
              ]
            , h4 [ class "modal-title"] [
                text ("Delete " ++ datasource.name)
              ]
            ]
          , div [ class "modal-body" ] [
              h4 [ class "text-center" ] [
                text "Are your sure you want to delete this datasource ?"
              ]
            ]
          , div [ class "modal-footer" ] [

                button [ type_ "button", class "btn btn-default", onClick (UpdateUI {ui | deleteModal = Nothing})] [
                  text "Cancel"
                ]
              , if model.hasWriteRights then
                  button [ type_ "button", class "btn btn-danger", onClick (DeleteCall datasource)] [
                    text "Delete"
                  ]
                else text ""
            ]
          ]
          ]
        ]
      Nothing -> text ""
  ]

